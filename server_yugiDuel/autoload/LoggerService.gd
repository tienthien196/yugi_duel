# ===========================================================================
# LoggerService.gd (Godot 3.6 Compatible)
# Autoload Singleton - Dịch vụ log không dùng màu, nhưng rõ ràng, có context
# Hỗ trợ: enter/exit, flow_step, trace_id, metadata, levels
# ===========================================================================

extends Node

# Cấp độ log
const LEVEL_DEBUG   = 0
const LEVEL_INFO    = 1
const LEVEL_WARN    = 2
const LEVEL_ERROR   = 3
const LEVEL_SUCCESS = 4

# Cấu hình
var min_level = LEVEL_DEBUG
var auto_trace = true

# Quản lý trace
var current_trace_id: String = ""

# Tên level (căn đều)
var level_names = {
	LEVEL_DEBUG:   "[DEBUG] ",
	LEVEL_INFO:    "[INFO ] ",
	LEVEL_WARN:    "[WARN ] ",
	LEVEL_ERROR:   "[ERROR] ",
	LEVEL_SUCCESS: "[SUCCESS]"
}

# Icon thay thế màu
var level_icons = {
	LEVEL_DEBUG:   "🔧",
	LEVEL_INFO:    "ℹ️",
	LEVEL_WARN:    "⚠️",
	LEVEL_ERROR:   "❌",
	LEVEL_SUCCESS: "✅"
}


# ===========================================================================
# _ready
# ===========================================================================
func _ready():
	print("[LOGGER] LoggerService đã khởi động.")


# ===========================================================================
# enter(source, action, from, data = {})
# ===========================================================================
func enter(source: String, action: String, from: String, data = {}):
	if LEVEL_INFO < min_level:
		return
	var trace = _get_trace()
	var msg = "%s %s %s → %s.%s()" % [trace, level_icons[LEVEL_INFO], from, source, action]
	_log(LEVEL_INFO, msg, data)
	current_trace_id = trace


# ===========================================================================
# exit(source, action, to, result = "success", duration = null, data = {})
# ===========================================================================
func exit(source: String, action: String, to: String, result: String = "success", duration = null, data = {}):
	if LEVEL_INFO < min_level:
		return
	var trace = _get_trace()
	var icon = level_icons[LEVEL_SUCCESS] if result ==  "success"  else level_icons[LEVEL_WARN]
	var time_str = " [%dms]" % duration if duration != null else ""
	var msg = "%s %s %s.%s() → %s %s%s" % [trace, icon, source, action, to, result, time_str]
	_log(LEVEL_SUCCESS  if result == "success" else LEVEL_WARN, msg, data)


# ===========================================================================
# flow_step(label, message, data = {})
# ===========================================================================
func flow_step(label: String, message: String, data = {}):
	if LEVEL_INFO < min_level:
		return
	var trace = _get_trace()
	var msg = "%s ℹ️  [%s] %s" % [trace, label, message]
	_log(LEVEL_INFO, msg, data)


# ===========================================================================
# Các hàm log cơ bản
# ===========================================================================
func info(msg: String, context: String = ""):
	var prefix = "%s: " % context if context != "" else ""
	_log(LEVEL_INFO, "ℹ️  " + prefix + msg)

func debug(msg: String, context: String = ""):
	_log(LEVEL_DEBUG, "🔧 " + ("%s: " % context  if context != "" else  "") + msg)

func warn(msg: String, context: String = "", data = {}):
	var full = { "msg": msg }
	if context: full["context"] = context
	if data: full["data"] = data
	_log(LEVEL_WARN, "⚠️  " + msg, full)

func error(msg: String, error_code: String = "", data = {}):
	var full = { "error_code": error_code }
	if data: full["data"] = data
	_log(LEVEL_ERROR, "❌ " + msg, full)

func success(msg: String, data = {}):
	_log(LEVEL_SUCCESS, "✅ " + msg, data)


# ===========================================================================
# set_min_level(level)
# ===========================================================================
func set_min_level(level):
	min_level = level

func enable_tracing(enable: bool):
	auto_trace = enable

func clear_trace():
	current_trace_id = ""


# ===========================================================================
# HÀM HỖ TRỢ
# ===========================================================================

func _get_trace() -> String:
	if current_trace_id == "" and auto_trace:
		current_trace_id = "t%06d" % (randi() % 1000000)
	return current_trace_id if current_trace_id != "" else "------"

func _log(level, message, metadata = null):
	if level < min_level:
		return

	var level_str = level_names.get(level, "[LOG] ")
	var timestamp = _get_timestamp()
	var full_msg = "%s[%s] %s" % [level_str, timestamp, message]
	print(full_msg)

	# In metadata nếu có (dạng JSON dễ đọc)
	if metadata:
		var meta_str = JSON.print(metadata, "    ")
		print("    %s" % meta_str)

func _get_timestamp() -> String:
	var t = OS.get_time()
	var ms = int((OS.get_unix_time() - int(OS.get_unix_time())) * 1000)
	return "%02d:%02d:%02d.%03d" % [t.hour, t.minute, t.second, ms]
