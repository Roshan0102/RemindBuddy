/**
 * RemindBuddy Cloud Functions - Entry Point
 * Modularized Architecture
 */

// Reminders & Tasks
export {
    processCalendarReminderTask,
    autoSnoozeReminderCheckTask,
    onCalendarReminderDeleted,
    onCalendarReminderUpdated,
    onCalendarReminderCreated
} from "./modules/reminders/calendarReminders";

// Collaboration
export {
    onCollaborationRequestCreated,
    onCollaborationRequestUpdated
} from "./modules/collaboration/collaborationTriggers";

// Gold Price & Chit Management
export {
    generateGoldAIInsights,
    generateGoldChitAdvice
} from "./modules/gold/goldAI";

export {
    checkGoldSources,
    forceGoldFetch,
    onGoldPriceCreated,
    onInstallmentUpdated
} from "./modules/gold/goldFunctions";

// Shifts & Roster Vision AI
export {
    analyzeRosterImage
} from "./modules/shifts/shiftVisionAI";

// Admin Management & GCP Billing
export {
    adminCreateUser,
    adminChangePassword,
    adminDeleteUser,
    adminUpdateUserModules,
    adminUpdateAllowedCollaborators
} from "./modules/admin/userManagement";

export {
    getGcpMonthlyCost
} from "./modules/admin/gcpBilling";

// Tech Events & Walk-ins
export {
    fetchUserTechEvents,
    fetchUserTechEventsTrigger
} from "./modules/events/techEvents";

export {
    fetchUserWalkIns,
    fetchUserWalkInsTrigger
} from "./modules/events/walkinDrives";

// Voice Assistant
export {
    voiceAssistantQuery
} from "./modules/voice/voiceAssistant";

// Job Assistant
export {
    parseJobPostersWithAI
} from "./modules/job_assistant/jobPosterAI";

export {
    generateManualJobApplicationWithAI,
    refineCoverLetterWithAI
} from "./modules/job_assistant/coverLetterAI";

export {
    sendJobApplicationEmail
} from "./modules/job_assistant/emailSender";

export {
    triggerAutoJobDiscoveryAndApply
} from "./modules/job_assistant/jobDiscoveryAI";

// Consolidated Master Schedulers
export {
    masterMinuteRunner,
    masterHalfHourlyRunner
} from "./schedulers/masterSchedulers";
