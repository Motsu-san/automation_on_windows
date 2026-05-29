import sys
import datetime
import time
from logging import StreamHandler, basicConfig, getLogger, handlers
from pathlib import Path

import jpholiday
import nest_asyncio
from playwright.sync_api import sync_playwright
from playwright.sync_api._generated import *

# pip install re time nest_asyncio dotenv playwright

nest_asyncio.apply()

# const
TIMEOUT_DEFAULT = 1000.0
DEFAULT_BODY_TEMPERATURE = "36.8"
DEFAULT_MEASURED_TIME = "7:00"
DEFAULT_PICKUP_TIME = "18:00"
DEFAULT_PICKUP_PERSON = "ママ"
CHILD_ID_1 = "2004104 32039"
CHILD_ID_2 = "2048054 32039"
LINK_CODMON = "https://parents.codmon.com"
_LOG_DIR = Path(__file__).parent / "log"
_LOG_DIR.mkdir(exist_ok=True)
PATH_CODMON_SCRIPT_LOG = _LOG_DIR / "codmon_auto_input_daily.log"

current_time = datetime.datetime.now()
logger = getLogger(__name__)
logger.setLevel("DEBUG")
rotatingfilehandler = handlers.RotatingFileHandler(
    PATH_CODMON_SCRIPT_LOG,
    encoding="utf-8",
    maxBytes=100 * 1024,
    backupCount=0,
)

MAIL_ADDRESS = "j4507620@yahoo.co.jp"


def does_selector_exist_by_text(page: Page, text: str):
    try:
        page.get_by_text(text).is_visible()
        return True
    except:
        return False


def inputDailyReport(child_name: str):
    # 連絡帳タブに切替
    page.locator('[data-test="notebookHeaderTab"]').get_by_text("連絡帳").click()
    time.sleep(2)
    try:
        page.wait_for_selector("div.list-header--default", timeout=TIMEOUT_DEFAULT)
        # page.get_by_text("送信済")
        logger.info(child_name + " report has been already sent")
    except:
        logger.info("Start input " + child_name + " report")
        # 体温のドロップダウンリストから特定の値を選択 X-pass 指定
        try:
            page.locator(
                '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[2]/section[4]/section/section/section/div/section[4]/div[3]/div[2]/div[1]/select'
            ).select_option(value=DEFAULT_BODY_TEMPERATURE)
            logger.info("input " + child_name + " body temperature")
        except:
            logger.info("cant input " + child_name + " body temperature")
        # 測定時間のドロップダウンリストから特定の値を選択
        try:
            page.locator(
                '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[2]/section[4]/section/section/section/div/section[4]/div[3]/div[2]/div[2]/select'
            ).select_option(value=DEFAULT_MEASURED_TIME)
            logger.info("input " + child_name + " measured time")
        except:
            logger.info("cant input " + child_name + " body temperature")
        # プールOKを選択
        if does_selector_exist_by_text(page, "プール"):
            page.get_by_text("OK").click()
            logger.info("input " + child_name + " pool play accepted")
        # 下書き保存
        page.locator("ons-button.button--large.button").get_by_text(
            "下書き保存"
        ).click()
        logger.info(child_name + " report has been sent successfully")


def inputPickupTime(child_name: str):
    # お迎えタブに切替
    page.locator('[data-test="notebookHeaderTab"]').get_by_text("お迎え").click()
    time.sleep(2)
    try:
        page.wait_for_selector(
            "div.notebook__extendStatus__title", timeout=TIMEOUT_DEFAULT
        )
        # page.locator('[data-test="extendNotification"]').get_by_text(
        #     DEFAULT_PICKUP_PERSON
        # ).click()
        logger.info(child_name + " pickup time has been already sent")
    except:
        # お迎え時間のドロップダウンリストから特定の値を選択
        try:
            page.locator(
                '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[2]/section[4]/div[1]/section[2]/section/div/div[1]/div/div[3]/div[2]/div[1]/select'
            ).select_option(DEFAULT_PICKUP_TIME)
            logger.info("input " + child_name + " pickup time")
        except:
            logger.info("cant input " + child_name + " pickup time")
        # 誰が？のドロップダウンリストから特定の値を選択 X-pass
        try:
            page.locator(
                '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[2]/section[4]/div[1]/section[2]/section/div/div[1]/div/div[3]/div[2]/div[2]/select'
            ).select_option(DEFAULT_PICKUP_PERSON)
            logger.info("input " + child_name + " pickup person")
        except:
            logger.info("cant input " + child_name + " pickup person")
        # 先生に連絡する
        page.locator(
            '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[2]/section[4]/div[1]/section[2]/section/div/div[2]/div[1]/ons-button'
        ).get_by_text("先生に連絡する").click()
        # 確認をOKする
        page.locator(
            "ons-alert-dialog-button.alert-dialog-button--primal.alert-dialog-button--rowfooter.alert-dialog-button"
        ).get_by_text("OK").click()

        try:
            page.wait_for_selector("div.notebook__extendStatus__title")
            logger.info(child_name + " pickup time has been sent successfully")
        except:
            logger.info("not finished " + child_name + " normally")


if __name__ == "__main__":
    handler = StreamHandler()
    handler.setLevel("INFO")
    basicConfig(handlers=[handler, rotatingfilehandler])
    basicConfig(level="DEBUG")
    logger.info("================ " + current_time.strftime("%Y/%m/%d %H:%M:%S.%f"))
    is_workday = current_time.weekday() < 5 and not jpholiday.is_holiday(current_time)
    if not is_workday:
        logger.info("Not needed to punch in/out")
        sys.exit()

    playwright = sync_playwright().start()

    user_data_dir = Path("data")

    browser = playwright.chromium.launch_persistent_context(
        headless=False,
        user_data_dir=user_data_dir,
        viewport=ViewportSize(width=1920, height=1280),
    )
    page = browser.pages[0]

    page.goto(LINK_CODMON)

    # Check if it has been login
    try:
        # 開いたページに連絡帳タブがあるか確認
        page.locator("button.tabbar__button")
        logger.info("already login")
    except:
        # 開いたページに連絡帳タブがない場合、ログインページにいるとして入力を待つ
        logger.info("Not login")
        page.click("div.menu__loginLink")
        page.wait_for_load_state("networkidle")
        page.wait_for_selector('input[autocomplete="email"]')
        # ユーザー名を入力
        page.fill('input[autocomplete="email"]', MAIL_ADDRESS)
        # パスワード入力をまつ
        page.wait_for_selector("ons-tab.notebookInActiveIcon.tabIcon.tabbar__item")

    # 連絡帳をクリック
    page.locator("button.tabbar__button").get_by_text("連絡").click()

    # 子供のドロップダウンリストから特定の値を選択
    page.locator(
        '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[1]/div/select'
    ).select_option(CHILD_ID_1)

    inputDailyReport("child#1")
    # inputPickupTime("child#1")

    # 子供のドロップダウンリストから特定の値を選択
    child_name = "2048054 32039"
    page.locator(
        '//*[@id="notebook_page"]/div[2]/ons-navigator/ons-page/div[2]/section[1]/div/select'
    ).select_option(CHILD_ID_2)

    inputDailyReport("child#2")
    # inputPickupTime("child#2")

    time.sleep(2)

    logger.info("has input them to codmon")
