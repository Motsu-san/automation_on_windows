SetTimer(CheckErrorPopup, 500)
SetTimer((*) => ExitApp(), 30000)

CheckErrorPopup() {
    if WinExist("Error") {
        text := WinGetText("Error")
        if InStr(text, "LoadLibrary failed with error 87") {
            WinActivate("Error")
            ControlClick("Button1", "Error")
        }
    }
}
