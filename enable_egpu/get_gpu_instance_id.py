import wmi
import sys

MY_GPU_INSTANCE_ID = 'PCI\\HOGE&HOGEHOGE&HOGEHOGEHOGE&HOGEHOGEHOGEHOGE\\0&0000000&0&00000000'

def get_gpu_instance_id():
    try:
        wmi_instance = wmi.WMI()
        display_info = wmi_instance.query("SELECT * FROM Win32_PnPEntity WHERE PNPClass='Display'")
        video_info = wmi_instance.query("SELECT * FROM Win32_VideoController")

        active_gpu = None
        for video in video_info:
            if video.CurrentNumberOfColors is not None:
                active_gpu = video.Caption
        print(f"Active GPU: {active_gpu}")

        for display in display_info:
            display_name = display.Caption
            display_device_id = display.DeviceID
            display_status = display.Status
            print(f"Device Name: {display.Name}")
            print(f"Device ID: {display.PNPDeviceID}")
            print(f"Status: {display.Status}")

            for video in video_info:
                if video.PNPDeviceID in display_device_id:
                    gpu_name = video.Caption
                    print(f"{display_name} is connected to {gpu_name}")

            if (display_device_id == MY_GPU_INSTANCE_ID):
                if (display_status == 'OK'):
                    print("My GPU is connected and OK.")
                else :
                    print("Something wrong on my GPU")
                    return display.PNPDeviceID

    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == "__main__":
    gpu_id = get_gpu_instance_id()
    if gpu_id:
        print(f"{gpu_id}")
        sys.exit(0)  # 正常終了
    else:
        print("Can't get gpu instance id")
        sys.exit(1)  # エラー終了
