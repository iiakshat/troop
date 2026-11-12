@tool
extends EditorPlugin
## Android export glue for the mixed audience (spec v2 §8). Editor-only; nothing here runs in
## the game.
## - Writes addons/AdmobPlugin/android_export.cfg from config/ads.json (the AdMob plugin puts
##   that app ID into the manifest), so the IDs live in one place.
## - Manifest: removes Firebase's auto-start provider (FirebaseInitProvider), so Firebase starts
##   only when Analytics.start_sdk() calls it for an adult; a child's device never starts it.
##   Turns off Firebase's advertising-ID and SSAID collection for everyone.

var _export: AndroidPrivacyExport


func _enter_tree() -> void:
	AndroidPrivacyExport.write_admob_export_cfg()
	_export = AndroidPrivacyExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null


class AndroidPrivacyExport extends EditorExportPlugin:
	const ADS_CONFIG := "res://config/ads.json"
	const ADMOB_EXPORT_CFG := "res://addons/AdmobPlugin/android_export.cfg"
	const MANIFEST := """
<meta-data android:name="google_analytics_adid_collection_enabled" android:value="false" />
<meta-data android:name="google_analytics_ssaid_collection_enabled" android:value="false" />
<provider
		android:name="com.google.firebase.provider.FirebaseInitProvider"
		android:authorities="${applicationId}.firebaseinitprovider"
		tools:node="remove" />
"""

	## The AdMob export config, derived from config/ads.json. Returns the app ID written.
	static func write_admob_export_cfg() -> String:
		var f := FileAccess.open(ADS_CONFIG, FileAccess.READ)
		if f == null:
			return ""
		var a: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not a is Dictionary:
			return ""
		var real := bool(a.get("is_real", false))
		var android: Dictionary = a.get("android", {})
		var test_id := String(android.get("test", {}).get("app_id", ""))
		var real_id := String(android.get("real", {}).get("app_id", ""))
		var cfg := ConfigFile.new()
		cfg.set_value("General", "is_real", real)
		cfg.set_value("Debug", "app_id", test_id)
		cfg.set_value("Release", "app_id", real_id if real_id != "" else test_id)
		var old := ConfigFile.new()
		if old.load(ADMOB_EXPORT_CFG) != OK or old.encode_to_text() != cfg.encode_to_text():
			cfg.save(ADMOB_EXPORT_CFG)
		return real_id if real else test_id


	func _get_name() -> String:
		return "SirenPrivacy"


	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		write_admob_export_cfg()


	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return MANIFEST
