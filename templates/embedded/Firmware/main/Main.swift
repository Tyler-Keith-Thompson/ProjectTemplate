import Greetings

/// The firmware's entry point, which ESP-IDF calls once FreeRTOS is running: greets on the serial
/// log once a second, forever.
@_cdecl("app_main")
func appMain() {
    let greeting = Greeting(name: "ProjectName").formal().punctuated(with: "!")
    var count = 0
    while true {
        count += 1
        print("\(greeting.text) (\(count))")
        vTaskDelay(UInt32(configTICK_RATE_HZ))
    }
}
