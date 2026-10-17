-- Marathon: a stream aimed at the default sink goes through its media
-- role's loopback, as a stream aimed nowhere does.
--
-- SPDX-License-Identifier: Apache-2.0
--
-- Qt's PipeWire audio connects every stream to its device's node, the
-- default one included, so WirePlumber takes that as a defined target and
-- its role policy (linking/find-media-role-target.lua) never sees the
-- stream; with the device held at full level it would play unscaled by the
-- media volume. WirePlumber already treats a node-defined target that is
-- the default as following the default (lutils.checkFollowDefault, after
-- PulseAudio); this extends that to the role policy. A target set in the
-- metadata, by moving the stream, still wins.

lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-linking")

function isDefault (om, si_props, defined)
  local direction = cutils.getTargetDirection (si_props)
  local default_id = cutils.getDefaultNode (si_props, direction)
  if default_id == nil then
    return false
  end
  local default = om:lookup {
    type = "SiLinkable",
    Constraint { "node.id", "=", tostring (default_id) },
  }
  if default == nil then
    return false
  end
  local props = default.properties
  return defined == props ["node.name"] or defined == props ["object.serial"] or
      defined == props ["node.id"]
end

function roleTarget (om, si_props)
  local role = si_props ["media.role"]
  for target in om:iterate {
    type = "SiLinkable",
    Constraint { "item.node.direction", "=", cutils.getTargetDirection (si_props) },
    Constraint { "device.intended-roles", "+" },
    Constraint { "media.type", "=", si_props ["media.type"] },
  } do
    for _, r in ipairs (Json.Raw (target.properties ["device.intended-roles"]):parse ()) do
      if r == role then
        return target
      end
    end
  end
  return nil
end

SimpleEventHook {
  name = "marathon/find-role-target-for-default",
  before = "linking/find-defined-target",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local _, om, si, si_props, _, target = lutils:unwrap_select_target_event (event)
    local defined = si_props ["target.object"] or si_props ["node.target"]
    if target or defined == nil or si_props ["media.role"] == nil or
        si_props ["node.link-group"] ~= nil then
      return
    end

    local metadata = cutils.get_default_metadata_object ()
    if metadata and (metadata:find (si_props ["node.id"], "target.object") or
        metadata:find (si_props ["node.id"], "target.node")) then
      return
    end

    if not isDefault (om, si_props, defined) then
      return
    end

    target = roleTarget (om, si_props)
    if target then
      log:info (si, string.format ("... default target taken as role %s: %s",
          si_props ["media.role"], tostring (target.properties ["node.name"])))
      event:set_data ("target", target)
    end
  end
}:register ()
