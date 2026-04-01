#include <napi.h>
#include <string>
#include <dispatch/dispatch.h>

#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <Contacts/Contacts.h>
#import <EventKit/EventKit.h>
#import <Photos/Photos.h>

#if __has_include(<Speech/Speech.h>)
#import <Speech/Speech.h>
#define HAS_SPEECH 1
#else
#define HAS_SPEECH 0
#endif

// =============================================================================
// Helper: status string constants
// =============================================================================

static std::string StatusGranted()       { return "granted"; }
static std::string StatusDenied()        { return "denied"; }
static std::string StatusNotDetermined() { return "not_determined"; }
static std::string StatusRestricted()    { return "restricted"; }
static std::string StatusLimited()       { return "limited"; }
static std::string StatusUnknown()       { return "unknown"; }

// =============================================================================
// Permission check implementations (all synchronous, safe from any thread)
// =============================================================================

static std::string CheckMicrophone() {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    switch (status) {
        case AVAuthorizationStatusAuthorized:    return StatusGranted();
        case AVAuthorizationStatusDenied:        return StatusDenied();
        case AVAuthorizationStatusRestricted:    return StatusRestricted();
        case AVAuthorizationStatusNotDetermined: return StatusNotDetermined();
        default:                                 return StatusUnknown();
    }
}

static std::string CheckCamera() {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusAuthorized:    return StatusGranted();
        case AVAuthorizationStatusDenied:        return StatusDenied();
        case AVAuthorizationStatusRestricted:    return StatusRestricted();
        case AVAuthorizationStatusNotDetermined: return StatusNotDetermined();
        default:                                 return StatusUnknown();
    }
}

static std::string CheckSpeechRecognition() {
#if HAS_SPEECH
    if (@available(macOS 10.15, *)) {
        SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized:    return StatusGranted();
            case SFSpeechRecognizerAuthorizationStatusDenied:        return StatusDenied();
            case SFSpeechRecognizerAuthorizationStatusRestricted:    return StatusRestricted();
            case SFSpeechRecognizerAuthorizationStatusNotDetermined: return StatusNotDetermined();
            default:                                                  return StatusUnknown();
        }
    }
#endif
    return StatusUnknown();
}

static std::string CheckLocation() {
    if (@available(macOS 11.0, *)) {
        CLLocationManager *manager = [[CLLocationManager alloc] init];
        CLAuthorizationStatus status = manager.authorizationStatus;
        switch (status) {
            case kCLAuthorizationStatusAuthorizedAlways:    return StatusGranted();
            case kCLAuthorizationStatusDenied:              return StatusDenied();
            case kCLAuthorizationStatusRestricted:          return StatusRestricted();
            case kCLAuthorizationStatusNotDetermined:       return StatusNotDetermined();
            default:                                        return StatusUnknown();
        }
    } else {
        CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        switch (status) {
            case kCLAuthorizationStatusAuthorizedAlways:    return StatusGranted();
            case kCLAuthorizationStatusDenied:              return StatusDenied();
            case kCLAuthorizationStatusRestricted:          return StatusRestricted();
            case kCLAuthorizationStatusNotDetermined:       return StatusNotDetermined();
            default:                                        return StatusUnknown();
        }
    }
}

static std::string CheckContacts() {
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    switch (status) {
        case CNAuthorizationStatusAuthorized:    return StatusGranted();
        case CNAuthorizationStatusDenied:        return StatusDenied();
        case CNAuthorizationStatusRestricted:    return StatusRestricted();
        case CNAuthorizationStatusNotDetermined: return StatusNotDetermined();
        default:                                 return StatusUnknown();
    }
}

static std::string CheckCalendars() {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    switch (status) {
        case EKAuthorizationStatusAuthorized:    return StatusGranted();
        case EKAuthorizationStatusDenied:        return StatusDenied();
        case EKAuthorizationStatusRestricted:    return StatusRestricted();
        case EKAuthorizationStatusNotDetermined: return StatusNotDetermined();
        default:
            if (@available(macOS 14.0, *)) {
                if (status == EKAuthorizationStatusFullAccess) return StatusGranted();
                if (status == EKAuthorizationStatusWriteOnly)  return StatusLimited();
            }
            return StatusUnknown();
    }
}

static std::string CheckReminders() {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
    switch (status) {
        case EKAuthorizationStatusAuthorized:    return StatusGranted();
        case EKAuthorizationStatusDenied:        return StatusDenied();
        case EKAuthorizationStatusRestricted:    return StatusRestricted();
        case EKAuthorizationStatusNotDetermined: return StatusNotDetermined();
        default:
            if (@available(macOS 14.0, *)) {
                if (status == EKAuthorizationStatusFullAccess) return StatusGranted();
            }
            return StatusUnknown();
    }
}

static std::string CheckPhotos() {
    if (@available(macOS 11.0, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        switch (status) {
            case PHAuthorizationStatusAuthorized:    return StatusGranted();
            case PHAuthorizationStatusDenied:        return StatusDenied();
            case PHAuthorizationStatusRestricted:    return StatusRestricted();
            case PHAuthorizationStatusNotDetermined: return StatusNotDetermined();
            case PHAuthorizationStatusLimited:       return StatusLimited();
            default:                                 return StatusUnknown();
        }
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        switch (status) {
            case PHAuthorizationStatusAuthorized:    return StatusGranted();
            case PHAuthorizationStatusDenied:        return StatusDenied();
            case PHAuthorizationStatusRestricted:    return StatusRestricted();
            case PHAuthorizationStatusNotDetermined: return StatusNotDetermined();
            default:                                 return StatusUnknown();
        }
    }
}

static std::string CheckBluetooth() {
    if (@available(macOS 10.15, *)) {
        CBManagerAuthorization auth = CBManager.authorization;
        switch (auth) {
            case CBManagerAuthorizationAllowedAlways:  return StatusGranted();
            case CBManagerAuthorizationDenied:          return StatusDenied();
            case CBManagerAuthorizationRestricted:      return StatusRestricted();
            case CBManagerAuthorizationNotDetermined:   return StatusNotDetermined();
            default:                                    return StatusUnknown();
        }
    }
    return StatusUnknown();
}

// =============================================================================
// Dispatch table for checks
// =============================================================================

static std::string CheckPermissionByType(const std::string& type) {
    if (type == "microphone")          return CheckMicrophone();
    if (type == "camera")              return CheckCamera();
    if (type == "speech_recognition")  return CheckSpeechRecognition();
    if (type == "location")            return CheckLocation();
    if (type == "contacts")            return CheckContacts();
    if (type == "calendars")           return CheckCalendars();
    if (type == "reminders")           return CheckReminders();
    if (type == "photos")              return CheckPhotos();
    if (type == "bluetooth")           return CheckBluetooth();
    return StatusUnknown();
}

// =============================================================================
// N-API: checkPermission (sync)
// =============================================================================

Napi::String CheckPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "String argument expected").ThrowAsJavaScriptException();
        return Napi::String::New(env, "unknown");
    }

    std::string type = info[0].As<Napi::String>().Utf8Value();
    std::string result = CheckPermissionByType(type);
    return Napi::String::New(env, result);
}

// =============================================================================
// Permission request implementations (dispatch to main thread, signal semaphore)
// =============================================================================

static void RequestMicrophone(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            result = granted ? StatusGranted() : StatusDenied();
            dispatch_semaphore_signal(sem);
        }];
    });
}

static void RequestCamera(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            result = granted ? StatusGranted() : StatusDenied();
            dispatch_semaphore_signal(sem);
        }];
    });
}

static void RequestSpeechRecognition(dispatch_semaphore_t sem, std::string& result) {
#if HAS_SPEECH
    if (@available(macOS 10.15, *)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                switch (status) {
                    case SFSpeechRecognizerAuthorizationStatusAuthorized:    result = StatusGranted(); break;
                    case SFSpeechRecognizerAuthorizationStatusDenied:        result = StatusDenied(); break;
                    case SFSpeechRecognizerAuthorizationStatusRestricted:    result = StatusRestricted(); break;
                    case SFSpeechRecognizerAuthorizationStatusNotDetermined: result = StatusNotDetermined(); break;
                    default:                                                  result = StatusUnknown(); break;
                }
                dispatch_semaphore_signal(sem);
            }];
        });
        return;
    }
#endif
    result = StatusUnknown();
    dispatch_semaphore_signal(sem);
}

static void RequestContacts(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CNContactStore *store = [[CNContactStore alloc] init];
        [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
            result = granted ? StatusGranted() : StatusDenied();
            dispatch_semaphore_signal(sem);
        }];
    });
}

static void RequestCalendars(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        EKEventStore *store = [[EKEventStore alloc] init];
        if (@available(macOS 14.0, *)) {
            [store requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError * _Nullable error) {
                result = granted ? StatusGranted() : StatusDenied();
                dispatch_semaphore_signal(sem);
            }];
        } else {
            [store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError * _Nullable error) {
                result = granted ? StatusGranted() : StatusDenied();
                dispatch_semaphore_signal(sem);
            }];
        }
    });
}

static void RequestReminders(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        EKEventStore *store = [[EKEventStore alloc] init];
        if (@available(macOS 14.0, *)) {
            [store requestFullAccessToRemindersWithCompletion:^(BOOL granted, NSError * _Nullable error) {
                result = granted ? StatusGranted() : StatusDenied();
                dispatch_semaphore_signal(sem);
            }];
        } else {
            [store requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL granted, NSError * _Nullable error) {
                result = granted ? StatusGranted() : StatusDenied();
                dispatch_semaphore_signal(sem);
            }];
        }
    });
}

static void RequestPhotos(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(macOS 11.0, *)) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                switch (status) {
                    case PHAuthorizationStatusAuthorized:    result = StatusGranted(); break;
                    case PHAuthorizationStatusDenied:        result = StatusDenied(); break;
                    case PHAuthorizationStatusRestricted:    result = StatusRestricted(); break;
                    case PHAuthorizationStatusLimited:       result = StatusLimited(); break;
                    case PHAuthorizationStatusNotDetermined: result = StatusNotDetermined(); break;
                    default:                                 result = StatusUnknown(); break;
                }
                dispatch_semaphore_signal(sem);
            }];
        } else {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                switch (status) {
                    case PHAuthorizationStatusAuthorized:    result = StatusGranted(); break;
                    case PHAuthorizationStatusDenied:        result = StatusDenied(); break;
                    case PHAuthorizationStatusRestricted:    result = StatusRestricted(); break;
                    case PHAuthorizationStatusNotDetermined: result = StatusNotDetermined(); break;
                    default:                                 result = StatusUnknown(); break;
                }
                dispatch_semaphore_signal(sem);
            }];
        }
    });
}

static void RequestBluetooth(dispatch_semaphore_t sem, std::string& result) {
    // Initializing CBCentralManager triggers the TCC dialog for Bluetooth.
    // We dispatch to main, create a manager, wait briefly for the dialog, then check status.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(macOS 10.15, *)) {
            // The init itself triggers the permission prompt
            dispatch_queue_t btQueue = dispatch_queue_create("com.moinsen.permissions.bt", DISPATCH_QUEUE_SERIAL);
            __attribute__((objc_precise_lifetime))
            CBCentralManager *manager = [[CBCentralManager alloc] initWithDelegate:nil queue:btQueue];
            (void)manager; // keep alive

            // Wait 1 second for the user to respond to the dialog
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                CBManagerAuthorization auth = CBManager.authorization;
                switch (auth) {
                    case CBManagerAuthorizationAllowedAlways:  result = StatusGranted(); break;
                    case CBManagerAuthorizationDenied:          result = StatusDenied(); break;
                    case CBManagerAuthorizationRestricted:      result = StatusRestricted(); break;
                    case CBManagerAuthorizationNotDetermined:   result = StatusNotDetermined(); break;
                    default:                                    result = StatusUnknown(); break;
                }
                dispatch_semaphore_signal(sem);
            });
        } else {
            result = StatusUnknown();
            dispatch_semaphore_signal(sem);
        }
    });
}

static void RequestLocation(dispatch_semaphore_t sem, std::string& result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CLLocationManager *manager = [[CLLocationManager alloc] init];
        [manager requestAlwaysAuthorization];

        // Location doesn't have a completion handler on macOS; poll after 2 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (@available(macOS 11.0, *)) {
                CLAuthorizationStatus status = manager.authorizationStatus;
                switch (status) {
                    case kCLAuthorizationStatusAuthorizedAlways:    result = StatusGranted(); break;
                    case kCLAuthorizationStatusDenied:              result = StatusDenied(); break;
                    case kCLAuthorizationStatusRestricted:          result = StatusRestricted(); break;
                    case kCLAuthorizationStatusNotDetermined:       result = StatusNotDetermined(); break;
                    default:                                        result = StatusUnknown(); break;
                }
            } else {
                CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
                switch (status) {
                    case kCLAuthorizationStatusAuthorizedAlways:    result = StatusGranted(); break;
                    case kCLAuthorizationStatusDenied:              result = StatusDenied(); break;
                    case kCLAuthorizationStatusRestricted:          result = StatusRestricted(); break;
                    case kCLAuthorizationStatusNotDetermined:       result = StatusNotDetermined(); break;
                    default:                                        result = StatusUnknown(); break;
                }
            }
            dispatch_semaphore_signal(sem);
        });
    });
}

// =============================================================================
// AsyncWorker: PermissionWorker
// =============================================================================

class PermissionWorker : public Napi::AsyncWorker {
public:
    PermissionWorker(Napi::Env env, const std::string& type, Napi::Promise::Deferred deferred)
        : Napi::AsyncWorker(env),
          type_(type),
          deferred_(deferred),
          result_(StatusUnknown()) {}

    void Execute() override {
        // First check current status — if already determined, return immediately
        std::string currentStatus = CheckPermissionByType(type_);
        if (currentStatus != StatusNotDetermined()) {
            result_ = currentStatus;
            return;
        }

        // Permission is not_determined — we need to trigger the request dialog.
        // macOS permission APIs must be called from the main thread.
        // We use dispatch_async to main queue + semaphore to wait for the result.
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        if (type_ == "microphone") {
            RequestMicrophone(sem, result_);
        } else if (type_ == "camera") {
            RequestCamera(sem, result_);
        } else if (type_ == "speech_recognition") {
            RequestSpeechRecognition(sem, result_);
        } else if (type_ == "contacts") {
            RequestContacts(sem, result_);
        } else if (type_ == "calendars") {
            RequestCalendars(sem, result_);
        } else if (type_ == "reminders") {
            RequestReminders(sem, result_);
        } else if (type_ == "photos") {
            RequestPhotos(sem, result_);
        } else if (type_ == "bluetooth") {
            RequestBluetooth(sem, result_);
        } else if (type_ == "location") {
            RequestLocation(sem, result_);
        } else {
            result_ = StatusUnknown();
            dispatch_semaphore_signal(sem);
        }

        // Wait up to 30 seconds for the permission dialog to be answered
        long timeout = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC));
        if (timeout != 0) {
            // Timeout — re-check current status as fallback
            result_ = CheckPermissionByType(type_);
        }
    }

    void OnOK() override {
        deferred_.Resolve(Napi::String::New(Env(), result_));
    }

    void OnError(const Napi::Error& error) override {
        deferred_.Reject(error.Value());
    }

private:
    std::string type_;
    Napi::Promise::Deferred deferred_;
    std::string result_;
};

// =============================================================================
// N-API: requestPermission (async, returns Promise)
// =============================================================================

Napi::Value RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "String argument expected").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    std::string type = info[0].As<Napi::String>().Utf8Value();

    Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
    auto* worker = new PermissionWorker(env, type, deferred);
    worker->Queue();
    return deferred.Promise();
}

// =============================================================================
// Module Init
// =============================================================================

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("checkPermission", Napi::Function::New(env, CheckPermission));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    return exports;
}

NODE_API_MODULE(permissions, Init)
