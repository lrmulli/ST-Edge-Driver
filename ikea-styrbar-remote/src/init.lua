local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local log = require "log"
local utils = require "st.utils"
local tradfri_remote_control = require "tradfri-remote-control"
log.info("Here we are")

defaults.register_for_default_handlers(tradfri_remote_control, tradfri_remote_control.supported_capabilities)

local driver = ZigbeeDriver("zigbee-button", tradfri_remote_control,tradfri_remote_control.supported_capabilities)
driver:run()