-- Copyright 2019-2020 Mitchell mitchell.att.foicica.com.

local M = {}

--[[ This comment is for LuaDoc.
---
-- Module that records buffer positions within Textadept views over time and
-- allows for navigating through that history.
--
-- By default, this module listens for text edit events, and each time an
-- insertion or deletion occurs, its location is appended to the current view's
-- location history. If the edit is close enough to the previous record, the
-- previous record is amended.
--
-- @field minimum_line_distance (number)
--   The minimum number of lines between distinct history records.
-- @field maximum_history_size (number)
--   The maximum number of history records to keep per view.
module('_M.history')]]

M.minimum_line_distance = 3
M.maximum_history_size = 100

-- Map of views to their history records.
-- Each record has a `pos` field that points to the current history position in
-- the associated view.
-- @class table
-- @name view_history
local view_history = {}
events.connect(events.VIEW_NEW, function() view_history[view] = {pos = 0} end)
-- TODO: consider view deletions?
events.connect(events.RESET_AFTER, function()
  for i = 1, #_VIEWS do view_history[_VIEWS[i]] = {pos = 0} end
end)

-- Listens for text insertion and deletion events and records their locations.
local function record_edit_location(modification_type, position, length)
  local buffer = buffer
  -- Only interested in text insertion or deletion.
  if modification_type & buffer.MOD_INSERTTEXT > 0 then
    if length == buffer.length then return end -- ignore file loading
    position = position + length
  elseif modification_type & buffer.MOD_DELETETEXT > 0 then
    if buffer.length == 0 then return end -- ignore replacing buffer contents
  else
    return
  end
  -- Ignore undo/redo.
  if modification_type &
     (buffer.PERFORMED_UNDO | buffer.PERFORMED_REDO) > 0 then
    return
  end
  M.append(buffer.filename or buffer._type or _L['Untitled'],
           buffer:line_from_position(position), buffer.column[position])
end

-- Enables recording of edit locations.
-- @name enable_listening
function M.enable_listening()
  events.disconnect(events.MODIFIED, record_edit_location)
  events.connect(events.MODIFIED, record_edit_location)
end

-- Disables recording of edit locations and clears all view history.
-- @name disable_listening
function M.disable_listening()
  events.disconnect(events.MODIFIED, record_edit_location)
  for _, history in pairs(view_history) do history = {pos = 0} end -- clear
end

-- Jumps to the current position in the current view's history.
local function goto_record()
  local history = view_history[view]
  local record = history[history.pos]
  if lfs.attributes(record[1]) then
    io.open_file(record[1])
  else
    for i = 1, #_BUFFERS do
      local buffer = _BUFFERS[i]
      if buffer.filename == record[1] or buffer._type == record[1] or
         not buffer.filename and not buffer._type and
         record[1] == _L['Untitled'] then
        view:goto_buffer(buffer)
        break
      end
    end
  end
  buffer:goto_pos(buffer:find_column(record[2], record[3]))
end

-- Navigates backwards through the current view's history.
-- @name back
function M.back()
  local history = view_history[view]
  if #history == 0 then return end -- nothing to do
  local record = history[history.pos]
  local line = buffer:line_from_position(buffer.current_pos)
  if buffer.filename ~= record[1] or
     math.abs(record[2] - line) > M.minimum_line_distance then
    -- When navigated away from the most recent record, jump back to that record
    -- first, then navigate backwards.
    goto_record()
    return
  end
  if history.pos > 1 then history.pos = history.pos - 1 end
  goto_record()
end

-- Navigates forwards through the current view's history.
-- @name forward
function M.forward()
  local history = view_history[view]
  if history.pos == #history then return end -- nothing to do
  history.pos = history.pos + 1
  goto_record()
end

-- Appends the given location to the current view's history.
-- @param filename String filename, buffer type, or identifier of the buffer to
--   store.
-- @param line Integer line number starting from 0 to store.
-- @param column Integer column number starting from 0 to store.
-- @name append
function M.append(filename, line, column)
  local history = view_history[view]
  if #history > 0 then
    local record = history[history.pos]
    if filename == record[1] and
       math.abs(record[2] - line) <= M.minimum_line_distance then
      -- When events are close enough to one another (distance-wise), update the
      -- most recent history position instead of appending a new one.
      record[2], record[3] = line, column
      return
    end
  end
  if history.pos < #history then
    for i = history.pos + 1, #history do history[i] = nil end -- clear forward
  end
  history[#history + 1] = {filename, line, column}
  if #history > M.maximum_history_size then table.remove(history, 1) end
  history.pos = #history
end

M.enable_listening()

-- Add menu entries.
local m_edit = textadept.menu.menubar[_L['_Edit']]
m_edit[#m_edit + 1] = {
  title = 'Histor_y',
  {'Navigate _Backward', M.back},
  {'Navigate _Forward', M.back},
  {''},
  {'_Disable', M.disable_listening},
  {'_Eisable', M.enable_listening},
}

return M
