extends Node
## Autoload "Updater": checks for a newer version of the game online and can
## download + install it as a PATCH.
##
## HOW IT WORKS
## 1. check() downloads a small JSON "manifest" from MANIFEST_URL, e.g.
##      {
##        "version":  "1.1.0",
##        "notes":    "New stage, faster drones",
##        "pck_url":  "https://github.com/you/tank-siege/releases/download/v1.1.0/tank-siege.pck",
##        "sha256":   "<SHA-256 of that .pck file>",
##        "page_url": "https://you.itch.io/tank-siege"
##      }
##    tools/make_update_manifest.py writes this file for you.
## 2. If "version" is newer than ours, the title screen offers the update.
## 3. download_and_install() downloads the .pck (a Godot resource pack: your
##    whole game's files), checks its SHA-256 so a broken download is never
##    used, and saves it in user://updates/.
## 4. On the next launch, _init() below mounts that pack BEFORE anything else
##    loads, so every scene, script and asset comes from the new version.
##
## LIMITS (good to know)
## - A patch can change scenes, scripts, art, sounds and music. It can't change
##   project.godot (window size, the autoload list, input settings) and can't
##   add new `class_name` scripts. For those, ship a full new download instead
##   (the title screen shows "Open download page" when page_url is set).
## - Patches are not used when running from the Godot editor (they would hide
##   your source files!), unless you pass --test-updates (see the README).
## - Rolling back: delete the user://updates folder.

signal status_changed

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, READY, FAILED }

## Where your update manifest lives. Leave empty to turn updates off.
## The GitHub build (.github/workflows/build.yml) attaches update.json to every
## Release, and this link always points at the newest Release's copy.
const MANIFEST_URL := "https://github.com/foxsoft2005/tank-siege/releases/latest/download/update.json"

const PATCH_DIR := "user://updates/"
const PATCH_FILE := PATCH_DIR + "patch.pck"
const PATCH_INFO := PATCH_DIR + "patch.cfg"
const VERSION_SCRIPT := "res://scripts/version.gd"

var state := State.IDLE
var current_version := "?"
var built_in_version := "?"
var patch_loaded := false
var latest := {}          # the manifest we downloaded
var progress := 0.0       # 0..1 while downloading
var error_text := ""
var manifest_url := MANIFEST_URL  # can be overridden for testing (--manifest=URL)


func _init() -> void:
	# _init runs when this autoload is CREATED: before the other autoloads and
	# before any scene is loaded. That's the moment to mount a patch.
	built_in_version = _read_version()
	_mount_patch()
	current_version = _read_version()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):
			manifest_url = arg.trim_prefix("--manifest=")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_configured() -> bool:
	return manifest_url != ""


## Auto-install only works in an exported game (or with --test-updates).
func can_auto_install() -> bool:
	return latest.get("pck_url", "") != "" and (not OS.has_feature("editor") or _testing())


# ---------------------------------------------------------------- checking

func check() -> void:
	if not is_configured() or state in [State.CHECKING, State.DOWNLOADING]:
		return
	_set_state(State.CHECKING)
	if not _url_allowed(manifest_url):
		_fail("the update URL must start with https://")
		return

	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	if http.request(manifest_url) != OK:
		http.queue_free()
		_fail("could not start the request")
		return
	# request_completed gives: result, HTTP status code, headers, body
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		_fail("no connection")
		return
	if response[1] != 200:
		_fail("server answered %d" % response[1])
		return

	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary or not (data as Dictionary).get("version", "") is String:
		_fail("the update file is not valid JSON")
		return
	latest = data
	_set_state(State.AVAILABLE if is_newer(latest["version"], current_version) else State.UP_TO_DATE)


## "1.10.0" is newer than "1.9.3": compare number by number, not as text.
static func is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := pa[i].to_int() if i < pa.size() else 0
		var nb := pb[i].to_int() if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false


# ---------------------------------------------------------------- installing

func download_and_install() -> void:
	if state != State.AVAILABLE or not can_auto_install():
		return
	var url: String = latest["pck_url"]
	var expected: String = str(latest.get("sha256", "")).to_lower()
	if not _url_allowed(url):
		_fail("the download URL must start with https://")
		return
	if expected.length() != 64:
		_fail("the update file has no valid sha256")
		return

	DirAccess.make_dir_recursive_absolute(PATCH_DIR)
	var part := PATCH_DIR + "download.part"
	var http := HTTPRequest.new()
	http.download_file = part          # stream straight to disk
	http.download_chunk_size = 65536
	http.timeout = 120.0
	add_child(http)
	progress = 0.0
	_set_state(State.DOWNLOADING)

	# A lambda can't re-assign an outer variable, but it can fill an array.
	var response := []
	http.request_completed.connect(func(r, code, headers, body) -> void:
		response.append_array([r, code, headers, body]))
	if http.request(url) != OK:
		http.queue_free()
		_fail("could not start the download")
		return
	# Poll every frame for progress until the download finishes.
	var last_step := -1
	while response.is_empty():
		await get_tree().process_frame
		var total := http.get_body_size()
		if total > 0:
			progress = float(http.get_downloaded_bytes()) / total
			var step := int(progress * 50)
			if step != last_step:  # don't flood the UI with updates
				last_step = step
				status_changed.emit()
	http.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		DirAccess.remove_absolute(part)
		_fail("download failed (%s)" % ("HTTP %d" % response[1] if response[0] == 0 else "no connection"))
		return
	# Integrity check: the file must match the fingerprint in the manifest.
	if file_sha256(part) != expected:
		DirAccess.remove_absolute(part)
		_fail("the download was damaged (checksum mismatch)")
		return

	DirAccess.remove_absolute(PATCH_FILE)
	DirAccess.rename_absolute(part, PATCH_FILE)
	var cfg := ConfigFile.new()
	cfg.set_value("patch", "version", latest["version"])
	cfg.set_value("patch", "sha256", expected)
	cfg.save(PATCH_INFO)
	progress = 1.0
	_set_state(State.READY)


## Start a fresh copy of the game and close this one. The new copy mounts the patch.
func restart_game() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()


# ---------------------------------------------------------------- startup patch

func _mount_patch() -> void:
	if not FileAccess.file_exists(PATCH_FILE):
		return
	if OS.has_feature("editor") and not _testing():
		return  # never hide your source files while developing
	var cfg := ConfigFile.new()
	if cfg.load(PATCH_INFO) != OK:
		_discard_patch("no patch info")
		return
	var patch_version: String = cfg.get_value("patch", "version", "0")
	# If the game itself was updated (full reinstall) past the patch, drop the patch.
	if not is_newer(patch_version, built_in_version):
		_discard_patch("patch v%s is not newer than v%s" % [patch_version, built_in_version])
		return
	# Check the file again: never load a damaged or modified pack.
	if file_sha256(PATCH_FILE) != cfg.get_value("patch", "sha256", ""):
		_discard_patch("checksum mismatch")
		return
	# replace_files = true: files in the patch win over the originals.
	if ProjectSettings.load_resource_pack(PATCH_FILE, true):
		patch_loaded = true
		print("Updater: running patch v", patch_version)
	else:
		_discard_patch("Godot could not load the pack")


func _discard_patch(reason: String) -> void:
	push_warning("Updater: ignoring downloaded patch (%s)" % reason)
	DirAccess.remove_absolute(PATCH_FILE)
	DirAccess.remove_absolute(PATCH_INFO)


## Read VERSION from version.gd, bypassing the cache so we see the patched copy.
func _read_version() -> String:
	var script := ResourceLoader.load(VERSION_SCRIPT, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if script == null:
		return "?"
	return str(script.get_script_constant_map().get("VERSION", "?"))


# ---------------------------------------------------------------- helpers

static func file_sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		ctx.update(f.get_buffer(65536))
	return ctx.finish().hex_encode()


## Only HTTPS (encrypted) — except plain http on this computer, for testing.
static func _url_allowed(url: String) -> bool:
	return url.begins_with("https://") or url.begins_with("http://localhost") \
		or url.begins_with("http://127.0.0.1")


func _testing() -> bool:
	return "--test-updates" in OS.get_cmdline_user_args()


func _set_state(s: State) -> void:
	state = s
	status_changed.emit()


func _fail(reason: String) -> void:
	error_text = reason
	push_warning("Updater: " + reason)
	_set_state(State.FAILED)
