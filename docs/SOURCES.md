# Source register


Sources below were consulted for this specification on 23 October 2026. Recheck relevant API availability, model artifacts, upstream build instructions, free-signing behavior, runner images, and billing before implementing a version-sensitive step. Preserve the chosen versions and actual observations in the project. Documentation establishes supported concepts, not successful end-to-end device behavior.

[S1] Apple, Developer account overview: https://developer.apple.com/help/account/basics/about-your-developer-account/

[S2] Apple, AVAudioSession playAndRecord: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord

[S3] Apple, AudioRecordingIntent: https://developer.apple.com/documentation/appintents/audiorecordingintent

[S4] Apple, IntentAuthenticationPolicy.alwaysAllowed: https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/alwaysallowed

[S5] Apple Developer Forums, AudioRecordingIntent/background activation discussion (diagnostic lead, not a universal guarantee): https://developer.apple.com/forums/thread/816408

[S6] GitHub CLI, gh repo create: https://cli.github.com/manual/gh_repo_create

[S7] GitHub CLI, gh auth status: https://cli.github.com/manual/gh_auth_status

[S8] GitHub, Actions billing: https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions

[S9] GitHub, Hosted runners reference: https://docs.github.com/en/actions/reference/runners/github-hosted-runners

[S10] sherpa-onnx, iOS build instructions: https://k2-fsa.github.io/sherpa/onnx/ios/build-sherpa-onnx-swift.html

[S11] XcodeGen, official repository: https://github.com/yonaskolb/XcodeGen

[S12] Apple, Preparing Metal to run in the background: https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background

[S13] Apple, FileProtectionType.completeUntilFirstUserAuthentication: https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication

[S14] Apple, Handling audio interruptions: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions

[S15] sherpa-onnx, streaming Zipformer model configurations: https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html

[S16] Model publisher, English streaming Zipformer: https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26

[S17] llama.cpp, Apple XCFramework documentation: https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md

[S18] Qwen, official Qwen2.5-1.5B-Instruct-GGUF repository: https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF

[S19] Apple, LiveActivityIntent: https://developer.apple.com/documentation/appintents/liveactivityintent

[S20] Apple, ActivityKit ContentState and Live Activities: https://developer.apple.com/documentation/activitykit/activityattributes/contentstate and https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities

[S21] Apple Support, Action Button: https://support.apple.com/en-ie/guide/iphone/iphe89d61d66/ios

[S22] Sideloadly, official site and FAQ: https://sideloadly.io/ and https://sideloadly.io/faq.html

[S23] Apple, Enabling Developer Mode: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device

**Evidence priority:** Actual reproducible results on the target device establish this implementation's behavior. Official documentation defines supported API contracts. Upstream repository/model documentation defines build and artifact requirements. Forum reports guide troubleshooting only. Never treat generated text or a prior assistant's confident description as verification.
