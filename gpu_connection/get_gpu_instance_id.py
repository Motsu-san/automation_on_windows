# get_gpu_instance_id.py
# PnP の Win32_PnPEntity から、自機のGPUデバイスを引き当て返す。
# マッチには .env の MY_GPU_HARDWARE_ID のみ使う（VEN/DEV/SUBSYS 等で機種を表すプレフィックス）。
# 同一のハードウェアIDを持つGPUを複数接続する構成では、どのデバイスか特定できないため
# その場合は使わないこと。
import wmi
import sys
from dotenv import load_dotenv
import os

load_dotenv(dotenv_path='.env')

# 機種識別用。PnPDeviceID 先頭に含まれる（InstanceId 全体の「\」より前の部分）。
my_gpu_hardware_id = os.getenv('MY_GPU_HARDWARE_ID')
print(f"MY_GPU_HARDWARE_ID: {my_gpu_hardware_id}")


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

            if my_gpu_hardware_id and (my_gpu_hardware_id in display_device_id):
                if (display_status == 'OK'):
                    print("My GPU is connected and OK.")
                    return display_device_id
                else :
                    print("Something wrong on my GPU")
                    return display_device_id
            else :
                print("ID is not matched.")
                print(f"Display Device ID:  {display_device_id}")
                print(f"MY_GPU_HARDWARE_ID: {my_gpu_hardware_id}")

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
