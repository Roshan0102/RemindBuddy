import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/services/assistant_service.dart';

void main() {
  group('AssistantService Privacy & Security Guardrails', () {
    test('isRestrictedFeature blocks sensitive Vault and Financial modules', () {
      expect(AssistantService.isRestrictedFeature('vault'), isTrue);
      expect(AssistantService.isRestrictedFeature('secure_vault'), isTrue);
      expect(AssistantService.isRestrictedFeature('finance'), isTrue);
      expect(AssistantService.isRestrictedFeature('bank_accounts'), isTrue);
      expect(AssistantService.isRestrictedFeature('expenses'), isTrue);
      expect(AssistantService.isRestrictedFeature('debts'), isTrue);
      expect(AssistantService.isRestrictedFeature('bills'), isTrue);

      // Safe features should NOT be restricted
      expect(AssistantService.isRestrictedFeature('gold'), isFalse);
      expect(AssistantService.isRestrictedFeature('gym'), isFalse);
      expect(AssistantService.isRestrictedFeature('reminders'), isFalse);
      expect(AssistantService.isRestrictedFeature('tasks'), isFalse);
      expect(AssistantService.isRestrictedFeature('job_assistant'), isFalse);
      expect(AssistantService.isRestrictedFeature('notes'), isFalse);
      expect(AssistantService.isRestrictedFeature('shifts'), isFalse);
    });

    test('isRestrictedQuery blocks sensitive voice queries', () {
      expect(AssistantService.isRestrictedQuery('What is my bank balance?'), isTrue);
      expect(AssistantService.isRestrictedQuery('Show my vault password'), isTrue);
      expect(AssistantService.isRestrictedQuery('What are my expenses today?'), isTrue);
      expect(AssistantService.isRestrictedQuery('Tell me my credit card credentials'), isTrue);
      expect(AssistantService.isRestrictedQuery('Show recent transactions'), isTrue);

      // Safe voice queries should NOT be restricted
      expect(AssistantService.isRestrictedQuery('What is today gold rate?'), isFalse);
      expect(AssistantService.isRestrictedQuery('Check gold price today'), isFalse);
      expect(AssistantService.isRestrictedQuery('Start my chest workout'), isFalse);
      expect(AssistantService.isRestrictedQuery('What is the weather today?'), isFalse);
      expect(AssistantService.isRestrictedQuery('Remind me to call mom at 5pm'), isFalse);
    });

    test('URI parsing for Assistant deep links correctly maps parameters', () {
      final goldUri = Uri.parse('smartbuddy://assistant?feature=gold');
      expect(goldUri.host, 'assistant');
      expect(goldUri.queryParameters['feature'], 'gold');

      final workoutUri = Uri.parse('smartbuddy://assistant?feature=gym&action=start_workout');
      expect(workoutUri.queryParameters['feature'], 'gym');
      expect(workoutUri.queryParameters['action'], 'start_workout');

      final reminderUri = Uri.parse('smartbuddy://assistant?feature=reminders&action=create');
      expect(reminderUri.queryParameters['feature'], 'reminders');
      expect(reminderUri.queryParameters['action'], 'create');

      final queryUri = Uri.parse('smartbuddy://assistant?query=What+is+quantum+computing');
      expect(queryUri.queryParameters['query'], 'What is quantum computing');
    });
  });
}
