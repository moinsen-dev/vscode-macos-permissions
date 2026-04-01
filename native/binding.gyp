{
  "targets": [
    {
      "target_name": "permissions",
      "sources": ["permissions.mm"],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "defines": [
        "NAPI_DISABLE_CPP_EXCEPTIONS"
      ],
      "conditions": [
        [
          "OS=='mac'",
          {
            "xcode_settings": {
              "OTHER_CFLAGS": [
                "-fobjc-arc",
                "-std=c++17"
              ],
              "OTHER_LDFLAGS": [
                "-framework", "AVFoundation",
                "-framework", "Speech",
                "-framework", "CoreLocation",
                "-framework", "Contacts",
                "-framework", "EventKit",
                "-framework", "Photos",
                "-framework", "CoreBluetooth",
                "-framework", "Foundation"
              ],
              "MACOSX_DEPLOYMENT_TARGET": "10.15",
              "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
              "CLANG_ENABLE_OBJC_ARC": "YES"
            }
          }
        ]
      ]
    }
  ]
}
