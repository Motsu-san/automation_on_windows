# get_gpu_instance_id.py
import wmi
import sys
from private_consts import MY_GPU_INSTANCE_ID
print(f"MY_GPU_INSTANCE_ID: {MY_GPU_INSTANCE_ID}")

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
            display_device_id = display.PNPDeviceID
            display_status = display.Status
            print("Display Info =====")
            print(f"Device Name: {display.Name}")
            print(f"Device ID: {display.PNPDeviceID}")
            print(f"Status: {display.Status}")

            for video in video_info:
                print("Video Info =====")
                print(f"Device ID: {video.PNPDeviceID}")
                if video.PNPDeviceID in display_device_id:
                    gpu_name = video.Caption
                    print(f"{display_name} is connected to {gpu_name}")

            if MY_GPU_INSTANCE_ID in display_device_id:
                if (display_status == 'OK'):
                    print("My GPU is connected and OK.")
                else :
                    print("Something wrong on my GPU")
                    return display_device_id
            else :
                print("ID is not matched.")
                print(f"Display Device ID:  {display_device_id}")
                print(f"MY GPU INSTANCE ID: {MY_GPU_INSTANCE_ID}")

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
        print(f"{gpu_id}")
        sys.exit(1)  # エラー終了
