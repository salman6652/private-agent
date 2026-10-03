import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? '',
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'make_call':
          final contactName = action.params['contact_name'] as String?;
          final phoneNumber = action.params['phone_number'] as String?;
          result = await _communication.makeCall(
            contactName: contactName,
            phoneNumber: phoneNumber,
          );
          // If contact wasn't found in system contacts address book, fallback to UI automation to find/call them on screen or in dialer!
          if (result.contains('Could not find contact') && contactName != null && aiService != null) {
            onProgress?.call('Contact not in address book. Searching screen and Phone app for "$contactName"...');
            _currentExecutor = TaskExecutor(
              aiService: aiService,
              screenService: _screenAutomation,
              appLauncher: _appLauncher,
              shizukuService: _shizuku,
              onProgress: onProgress,
            );
            result = await _currentExecutor!.executeTask(
              'Call "$contactName". Check the screen, dialer, recent calls, or missed call banner for "$contactName" or "Call back" and tap to call.',
            );
            _currentExecutor = null;
          }
          break;

        case 'send_sms':
          final smsContact = action.params['contact_name'] as String?;
          final smsNumber = action.params['phone_number'] as String?;
          final message = action.params['message'] as String? ?? '';
          result = await _communication.sendSms(
            contactName: smsContact,
            phoneNumber: smsNumber,
            message: message,
          );
          if (result.contains('Could not find contact') && smsContact != null && aiService != null) {
            onProgress?.call('Searching screen for "$smsContact" to send SMS...');
            _currentExecutor = TaskExecutor(
              aiService: aiService,
              screenService: _screenAutomation,
              appLauncher: _appLauncher,
              shizukuService: _shizuku,
              onProgress: onProgress,
            );
            result = await _currentExecutor!.executeTask(
              'Find "$smsContact" and send message: "$message"',
            );
            _currentExecutor = null;
          }
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: (action.params['hour'] as num?)?.toInt() ?? 0,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: (action.params['seconds'] as num?)?.toInt() ?? 60,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        // ─── Screen Automation Actions ────────────────────────

        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────

        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          result = await _currentExecutor!.executeTask(goal);
          _currentExecutor = null;
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }
}
