-- Marathon: earpiece or loudspeaker for a voice call.
--
-- SPDX-License-Identifier: Apache-2.0
--
-- WirePlumber selects a card's call profile while ModemManager has a voice
-- call (device/find-voice-call-profile.lua). This narrows that choice by the
-- marathon.call.speakerphone setting: among call profiles that differ by
-- output (or the two a device names in marathon.call.profile and
-- marathon.call.speaker-profile), and among a call profile's output routes.

cutils = require ("common-utils")
devinfo = require ("device-info-cache")
log = Log.open_topic ("s-device")

in_call = false

alsa_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "alsa" },
  }
}

function speakerphone ()
  return Settings.get_boolean ("marathon.call.speakerphone")
end

function isSpeaker (name)
  return name ~= nil and string.find (string.lower (name), "speaker", 1, true) ~= nil
end

function reselect ()
  local source = Plugin.find ("standard-event-source")
  for device in alsa_devs_om:iterate () do
    source:call ("push-event", "select-profile", device, nil)
  end
end

mm = Plugin.find ("modem-manager")
mm:connect ("voice-call-start", function ()
  in_call = true
end)
mm:connect ("voice-call-stop", function ()
  in_call = false
end)

Settings.subscribe ("marathon.call.speakerphone", function ()
  if in_call then
    reselect ()
  end
end)

SimpleEventHook {
  name = "marathon/find-call-profile",
  before = "device/find-calling-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    if not in_call or event:get_data ("selected-profile") then
      return
    end

    local device = event:get_subject ()
    local speaker = speakerphone ()
    local named = device.properties [speaker and "marathon.call.speaker-profile"
        or "marathon.call.profile"]
    local best = nil

    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      if profile and profile.available ~= "no" then
        if named then
          if profile.name == named then
            best = profile
          end
        elseif string.find (profile.name, "^Voice Call") and
            isSpeaker (profile.name) == speaker and
            (best == nil or profile.priority > best.priority) then
          best = profile
        end
      end
    end

    if best then
      log:info (device, "call profile " .. best.name)
      event:set_data ("selected-profile", best)
    end
  end
}:register ()

-- Toggling within the same profile changes no profile, so nothing would
-- reselect the routes.
SimpleEventHook {
  name = "marathon/reselect-call-routes",
  after = "device/apply-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    if not in_call then
      return
    end

    local device = event:get_subject ()
    local dev_info = devinfo:get_device_info (device)
    local selected = event:get_data ("selected-profile")
    if not dev_info or not selected or selected.index ~= dev_info.active_profile then
      return
    end

    local ids = {}
    for _, ri in pairs (dev_info.route_infos) do
      if ri.profiles == nil or cutils.arrayContains (ri.profiles, dev_info.active_profile) then
        for _, id in ipairs (ri.devices) do
          if not cutils.arrayContains (ids, id) then
            table.insert (ids, id)
          end
        end
      end
    end

    Plugin.find ("standard-event-source"):call ("push-event", "select-routes", device, {
      ["profile.active-device-ids"] = Json.Array (ids):to_string (),
    })
  end
}:register ()

SimpleEventHook {
  name = "marathon/find-call-routes",
  before = "device/find-stored-routes",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-routes" },
      Constraint { "profile.active-device-ids", "is-present" },
    },
  },
  execute = function (event)
    if not in_call then
      return
    end

    local device = event:get_subject ()
    local dev_info = devinfo:get_device_info (device)
    if not dev_info then
      return
    end

    local ids = Json.Raw (event:get_properties () ["profile.active-device-ids"]):parse ()
    local selected = event:get_data ("selected-routes") or Properties ()
    local speaker = speakerphone ()

    for _, id in ipairs (ids) do
      local best = nil
      for _, ri in pairs (dev_info.route_infos) do
        if ri.direction == "Output" and ri.available ~= "no" and
            cutils.arrayContains (ri.devices, id) and
            (ri.profiles == nil or cutils.arrayContains (ri.profiles, dev_info.active_profile)) and
            isSpeaker (ri.name) == speaker and
            (best == nil or ri.priority > best.priority) then
          best = ri
        end
      end
      if best then
        log:info (device, "call route " .. best.name)
        selected [tostring (id)] = Json.Object { index = best.index }:to_string ()
      end
    end

    event:set_data ("selected-routes", selected)
  end
}:register ()

alsa_devs_om:activate ()
