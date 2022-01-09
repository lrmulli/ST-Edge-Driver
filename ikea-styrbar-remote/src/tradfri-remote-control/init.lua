local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local Level = zcl_clusters.Level
local Scenes = zcl_clusters.Scenes
local PowerConfiguration = zcl_clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local zdo_messages = require "st.zigbee.zdo"
local utils = require "st.utils"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"


local is_tradfri_remote_control = function(opts, driver, device)
  local is_tradfri_on_off = device:get_manufacturer() == "IKEA of Sweden" and device:get_model() == "TRADFRI remote control"
  log.debug("Is Tradfri Remote Control: " .. tostring(is_tradfri_on_off))
  return is_tradfri_on_off
end

function toggle_handler_up(driver, device, value, zb_rx)
  log.debug("Handling Tradfri TOGGLE - UP")
  device:emit_event_for_endpoint(1, capabilities.button.button.pushed({ state_change = true }))
  device:emit_event(capabilities.button.button.pushed({ state_change = true }))
end
function toggle_handler_down(driver, device, value, zb_rx)
    log.debug("Handling Tradfri TOGGLE - DOWN")
    device:emit_event_for_endpoint(2, capabilities.button.button.pushed({ state_change = true }))
    device:emit_event(capabilities.button.button.pushed({ state_change = true }))
  end


function held_up_handler(driver, device, value, zb_rx)
  log.debug("Handling Tradfri held UP")
  device:emit_event_for_endpoint(1, capabilities.button.button.held({ state_change = true }))
  device:emit_event(capabilities.button.button.held({ state_change = true }))
end


function held_down_handler(driver, device, value, zb_rx)
  log.debug("Handling Tradfri held DOWN")
  device:emit_event_for_endpoint(2, capabilities.button.button.held({ state_change = true }))
  device:emit_event(capabilities.button.button.held({ state_change = true }))
end

local function left_right_pushed_handler(driver, device, zb_rx)
  log.debug("Handling Tradfri left/right button PUSHED, value: " .. zb_rx.body.zcl_body.body_bytes:byte(1))
  -- Skip if left or right are button held
  if(zb_rx.body.zcl_body.body_bytes:byte(1) ~= 2) then
    local button_number = zb_rx.body.zcl_body.body_bytes:byte(1) == 0 and 4 or 3
    log.debug("Button Number: ".. button_number)
    device:emit_event_for_endpoint(button_number, capabilities.button.button.pushed({ state_change = true }))
    device:emit_event(capabilities.button.button.pushed({ state_change = true }))
  end
end

local function left_right_held_handler(driver, device, zb_rx)
  log.debug("Handling Tradfri left/right button HELD, value: " .. zb_rx.body.zcl_body.body_bytes:byte(1))
  local button_number = zb_rx.body.zcl_body.body_bytes:byte(1) == 1 and 3 or 4
  device:emit_event_for_endpoint(button_number, capabilities.button.button.held({ state_change = true }))
  device:emit_event(capabilities.button.button.held({ state_change = true }))
end

function not_held_handler(driver, device, value, zb_rx)
  log.debug("Handling Tradfri not held. Nothing to do.")
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("button(%d)")
  return { ep_num and tonumber(ep_num) } or {}
end

local function endpoint_to_component(device, ep)
  local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end
end

local function device_configure(driver, device, event, args)
  log.debug("Configuring device")
  local addr_header = messages.AddressHeader(
          constants.HUB.ADDR,
          constants.HUB.ENDPOINT,
          device:get_short_address(),
          device.fingerprinted_endpoint_id,
          constants.ZDO_PROFILE_ID,
          mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )
  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0)
  local message_body = zdo_messages.ZdoMessageBody({
    zdo_body = binding_table_req
  })
  local binding_table_cmd = messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = message_body
  })
  device:send(binding_table_cmd)
  device_management.configure(driver, device)
end

local function device_added(driver, device)
  log.info("Device added handler")
  device:refresh()  -- for battery state. Needed?
end

local function device_init(driver, device, event, args)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  device:emit_event(capabilities.button.numberOfButtons(4))
  device:emit_event(capabilities.button.supportedButtonValues({'pushed', 'held'}))
  device:emit_event(capabilities.button.button.pushed())
  for i = 1, 4 do
    device:emit_event_for_endpoint(i, capabilities.button.numberOfButtons(1))
    device:emit_event_for_endpoint(i, capabilities.button.supportedButtonValues({'pushed', 'held'}))
    device:emit_event_for_endpoint(i, capabilities.button.button.pushed())
  end
end

local function battery_perc_attr_handler(driver, device, value, zb_rx)
  local perc = value.value  -- Some Tradfri devices present value in percentage without dividing by 2, is it correct for Remote Control?
  device:emit_event(capabilities.battery.battery(math.min(perc, 100)))
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  log.debug("Received ZDO binding table message")
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      local group = binding_table.dest_addr.value
      log.debug("Adding hub to group: " .. tostring(group))
      driver:add_hub_to_zigbee_group(group)
    end
  end
end

local tradfri_remote_control = {
  NAME = "IKEA Tradfri Remote Control",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = device_configure
  },
  supported_capabilities = {
    capabilities.battery,
    capabilities.button,
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    },
    cluster = {
      [OnOff.ID] = {
        [0x01] = toggle_handler_up,
        [0x00] = toggle_handler_down
      },
      [Level.ID] = {
        [Level.commands.MoveWithOnOff.ID] = held_up_handler,
        [Level.commands.StopWithOnOff.ID] = not_held_handler,

        [Level.commands.Move.ID] = held_down_handler,
        [Level.commands.Stop.ID] = not_held_handler
      },
      [Scenes.ID] = {
        [0x07] = left_right_pushed_handler,
        [0x08] = left_right_held_handler,
        [0x09] = not_held_handler
      }
    },
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    }
  },
  can_handle = is_tradfri_remote_control
}

return tradfri_remote_control