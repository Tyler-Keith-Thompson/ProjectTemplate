import Greetings

/// The firmware's entry point, which ESP-IDF calls once FreeRTOS is running: greets on the serial
/// log once a second, forever.
@_cdecl("app_main")
func appMain() {
    guard let greeting = try? Greeting(name: "ProjectName").formal().punctuated(with: "!") else {
        print("No greeting: the name is empty")
        return
    }
    var count = 0
    while true {
        count += 1
        print("\(greeting.text) (\(count))")
        vTaskDelay(UInt32(configTICK_RATE_HZ))
    }
}
