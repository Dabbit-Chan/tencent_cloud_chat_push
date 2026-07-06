import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
} from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import { Context as TIMPushContext } from '@ohos.abilityAccessCtrl';
import notificationManager from '@ohos.notificationManager';
import { TIMPushListener, TIMPushManager, TIMPushMessage, TIMPushResult } from '@tencentcloud/timpush';

/** TencentCloudChatPushPlugin **/
export default class TencentCloudChatPushPlugin implements FlutterPlugin, MethodCallHandler, TIMPushListener, AbilityAware, NewWantListener {
  private channel: MethodChannel | null = null;
  private context: TIMPushContext | null = null;
  private hasAddedPushListener: boolean = false;
  private hasRegisteredNotificationClickedEvent: boolean = false;
  private pendingNotificationClickedExts: Array<string> = [];

  constructor() {
  }

  getUniqueClassName(): string {
    return "TencentCloudChatPushPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext() as TIMPushContext
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "tencent_cloud_chat_push");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.channel = null
    this.context = null
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    const launchWant = binding.getAbility().launchWant;
    if (launchWant !== null && launchWant !== undefined) {
      this.handleNotificationClickedWant(launchWant);
    }
    binding.addOnNewWantListener(this);
  }

  onDetachedFromAbility(): void {
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    this.handleNotificationClickedWant(want);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "registerOnNotificationClickedEvent":
        this.registerOnNotificationClickedEvent(result);
        break;
      case "registerPush":
        this.registerPush(call, result);
        break;
      case "unRegisterPush":
        this.unRegisterPush(call, result);
        break;
      case "getRegistrationID":
        this.getRegistrationID(call, result);
        break;
      case "setRegistrationID":
        this.setRegistrationID(call, result);
        break;
      case "addPushListener":
        this.addPushListener(call, result);
        break;
      case "disablePostNotificationInForeground":
        this.disablePostNotificationInForeground(call, result);
        break;
      case "syncBadgeNumber":
        this.syncBadgeNumber(call, result);
        break;
      case "callExperimentalAPI":
        this.callExperimentalAPI(call, result);
        break;
      default:
        result.notImplemented()
    }
  }

  private registerOnNotificationClickedEvent(result: MethodResult): void {
    this.hasRegisteredNotificationClickedEvent = true;
    this.flushPendingNotificationClickedExts();
    result.success("")
  }

  private registerPush(_call: MethodCall, result: MethodResult): void {
    if (this.context === null) {
      this.fail(result, "-1", "Application context is null");
      return
    }

    const sdkAppIdString: string = this.optArgument(_call, "sdkAppId", "0");
    const sdkAppId: number = Number.parseInt(sdkAppIdString);
    const appKey: string = this.optArgument(_call, "appKey", "");
    const ohosCertificateID: number = this.optArgument(_call, "ohosCertificateID", 0);
    TIMPushManager.getInstance()
      .registerPush(this.context, sdkAppId, appKey.length > 0 ? appKey : undefined, ohosCertificateID > 0 ? ohosCertificateID : undefined)
      .then((pushResult: TIMPushResult) => {
        this.handlePushResult(pushResult, result)
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  private unRegisterPush(_call: MethodCall, result: MethodResult): void {
    TIMPushManager.getInstance()
      .unRegisterPush()
      .then((pushResult: TIMPushResult) => {
        this.handlePushResult(pushResult, result)
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  private getRegistrationID(_call: MethodCall, result: MethodResult): void {
    TIMPushManager.getInstance()
      .getRegistrationID()
      .then((pushResult: TIMPushResult) => {
        this.handlePushResult(pushResult, result)
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  private setRegistrationID(_call: MethodCall, result: MethodResult): void {
    const registrationID: string = this.optArgument(_call, "registrationID", "");
    TIMPushManager.getInstance()
      .setRegistrationID(registrationID)
      .then((pushResult: TIMPushResult) => {
        this.handlePushResult(pushResult, result)
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  private addPushListener(_call: MethodCall, result: MethodResult): void {
    if (!this.hasAddedPushListener) {
      TIMPushManager.getInstance().addPushListener(this);
      this.hasAddedPushListener = true;
    }
    this.flushPendingNotificationClickedExts();
    result.success("")
  }

  private disablePostNotificationInForeground(_call: MethodCall, result: MethodResult): void {
    const disableString: string = this.optArgument(_call, "disablePostNotificationInForeground", "false");
    TIMPushManager.getInstance().disablePostNotificationInForeground(disableString === "true")
    result.success("")
  }

  private syncBadgeNumber(_call: MethodCall, result: MethodResult): void {
    const badgeNumber: number = this.optArgument(_call, "badgeNumber", 0);
    this.setBadgeNumber(badgeNumber)
      .then(() => {
        result.success("")
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  private callExperimentalAPI(_call: MethodCall, result: MethodResult): void {
    const api: string = this.optArgument(_call, "api", "");
    const param: Object | null = this.optArgument(_call, "param", null);
    TIMPushManager.getInstance()
      .callExperimentalAPI(api, param)
      .then((pushResult: TIMPushResult) => {
        this.handlePushResult(pushResult, result)
      })
      .catch((error: Error) => {
        this.fail(result, "-1", error.message)
      })
  }

  onMessageReceived(message: TIMPushMessage): void {
    const data: Map<string, string> = new Map();
    data.set("title", message.title);
    data.set("desc", message.desc);
    data.set("ext", message.ext);
    data.set("messageID", message.messageID);
    this.invokeFlutter("onRecvPushMessage", data);
  }

  onRevokePushMessage(messageID: string): void {
    this.invokeFlutter("onRevokePushMessage", messageID);
  }

  onNotificationClicked(ext: string): void {
    this.dispatchNotificationClicked(ext);
  }

  private handleNotificationClickedWant(want: Want): void {
    if (!this.isTIMPushClickWant(want)) {
      return;
    }
    const ext = this.getPushExt(want);
    if (ext.length === 0) {
      return;
    }
    this.dispatchNotificationClicked(ext);
  }

  private isTIMPushClickWant(want: Want): boolean {
    const action = want.action;
    const uri = want.uri;
    if (action === 'com.timpush.action') {
      return true;
    }
    return uri !== undefined && uri !== null && uri.includes('com.tencent.timpush');
  }

  private getPushExt(want: Want): string {
    const parameters = want.parameters;
    if (parameters === null || parameters === undefined) {
      return '';
    }
    const ext = parameters['ext'];
    if (typeof ext === 'string') {
      return ext;
    }
    return '';
  }

  private dispatchNotificationClicked(ext: string): void {
    if (!this.canDispatchNotificationClicked()) {
      this.pendingNotificationClickedExts.push(ext);
      return;
    }
    this.invokeFlutter("onNotificationClicked", ext);
    this.invokeFlutter("on_notification_clicked", ext);
  }

  private canDispatchNotificationClicked(): boolean {
    return this.channel !== null && (this.hasRegisteredNotificationClickedEvent || this.hasAddedPushListener);
  }

  private flushPendingNotificationClickedExts(): void {
    if (!this.canDispatchNotificationClicked()) {
      return;
    }
    const pendingExts = this.pendingNotificationClickedExts;
    this.pendingNotificationClickedExts = [];
    pendingExts.forEach((ext: string): void => {
      this.dispatchNotificationClicked(ext);
    });
  }

  private setBadgeNumber(totalUnreadCount: number): Promise<void> {
    const badgeNumber = Math.max(0, Math.floor(totalUnreadCount));
    console.info(`TencentCloudChatPushPlugin syncBadgeNumber: badgeNumber=${badgeNumber}`);
    return notificationManager.setBadgeNumber(badgeNumber);
  }

  private handlePushResult(pushResult: TIMPushResult, result: MethodResult): void {
    if (pushResult.code === 0) {
      result.success(pushResult.data ?? "")
      return
    }
    this.fail(result, pushResult.code.toString(), pushResult.message ?? "", pushResult.data as Object)
  }

  private invokeFlutter(method: string, data: Object | string): void {
    if (this.channel !== null) {
      this.channel.invokeMethod(method, data)
    }
  }

  private fail(result: MethodResult, code: string, message: string, details: Object | null = null): void {
    result.error(code, message, details)
  }

  private optArgument<T>(call: MethodCall, key: string, defaultValue: T): T {
    try {
      return call.argument(key);
    } catch (e) {
      return defaultValue;
    }
  }
}
