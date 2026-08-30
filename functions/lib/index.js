"use strict";
/**
 * RemindBuddy Cloud Functions - Entry Point
 * Modularized Architecture
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.masterHalfHourlyRunner = exports.masterMinuteRunner = exports.triggerAutoJobDiscoveryAndApply = exports.sendJobApplicationEmail = exports.refineCoverLetterWithAI = exports.generateManualJobApplicationWithAI = exports.parseJobPostersWithAI = exports.voiceAssistantQuery = exports.fetchUserWalkInsTrigger = exports.fetchUserWalkInDrives = exports.fetchUserWalkIns = exports.fetchUserTechEventsTrigger = exports.fetchUserTechEvents = exports.getGcpMonthlyCost = exports.adminUpdateAllowedCollaborators = exports.adminUpdateUserModules = exports.adminDeleteUser = exports.adminChangePassword = exports.adminCreateUser = exports.analyzeRosterImage = exports.onInstallmentUpdated = exports.onGoldPriceCreated = exports.forceGoldFetch = exports.checkGoldSources = exports.generateGoldChitAdvice = exports.generateGoldAIInsights = exports.onCollaborationRequestUpdated = exports.onCollaborationRequestCreated = exports.onCalendarReminderCreated = exports.onCalendarReminderUpdated = exports.onCalendarReminderDeleted = exports.autoSnoozeReminderCheckTask = exports.processCalendarReminderTask = void 0;
// Reminders & Tasks
var calendarReminders_1 = require("./modules/reminders/calendarReminders");
Object.defineProperty(exports, "processCalendarReminderTask", { enumerable: true, get: function () { return calendarReminders_1.processCalendarReminderTask; } });
Object.defineProperty(exports, "autoSnoozeReminderCheckTask", { enumerable: true, get: function () { return calendarReminders_1.autoSnoozeReminderCheckTask; } });
Object.defineProperty(exports, "onCalendarReminderDeleted", { enumerable: true, get: function () { return calendarReminders_1.onCalendarReminderDeleted; } });
Object.defineProperty(exports, "onCalendarReminderUpdated", { enumerable: true, get: function () { return calendarReminders_1.onCalendarReminderUpdated; } });
Object.defineProperty(exports, "onCalendarReminderCreated", { enumerable: true, get: function () { return calendarReminders_1.onCalendarReminderCreated; } });
// Collaboration
var collaborationTriggers_1 = require("./modules/collaboration/collaborationTriggers");
Object.defineProperty(exports, "onCollaborationRequestCreated", { enumerable: true, get: function () { return collaborationTriggers_1.onCollaborationRequestCreated; } });
Object.defineProperty(exports, "onCollaborationRequestUpdated", { enumerable: true, get: function () { return collaborationTriggers_1.onCollaborationRequestUpdated; } });
// Gold Price & Chit Management
var goldAI_1 = require("./modules/gold/goldAI");
Object.defineProperty(exports, "generateGoldAIInsights", { enumerable: true, get: function () { return goldAI_1.generateGoldAIInsights; } });
Object.defineProperty(exports, "generateGoldChitAdvice", { enumerable: true, get: function () { return goldAI_1.generateGoldChitAdvice; } });
var goldFunctions_1 = require("./modules/gold/goldFunctions");
Object.defineProperty(exports, "checkGoldSources", { enumerable: true, get: function () { return goldFunctions_1.checkGoldSources; } });
Object.defineProperty(exports, "forceGoldFetch", { enumerable: true, get: function () { return goldFunctions_1.forceGoldFetch; } });
Object.defineProperty(exports, "onGoldPriceCreated", { enumerable: true, get: function () { return goldFunctions_1.onGoldPriceCreated; } });
Object.defineProperty(exports, "onInstallmentUpdated", { enumerable: true, get: function () { return goldFunctions_1.onInstallmentUpdated; } });
// Shifts & Roster Vision AI
var shiftVisionAI_1 = require("./modules/shifts/shiftVisionAI");
Object.defineProperty(exports, "analyzeRosterImage", { enumerable: true, get: function () { return shiftVisionAI_1.analyzeRosterImage; } });
// Admin Management & GCP Billing
var userManagement_1 = require("./modules/admin/userManagement");
Object.defineProperty(exports, "adminCreateUser", { enumerable: true, get: function () { return userManagement_1.adminCreateUser; } });
Object.defineProperty(exports, "adminChangePassword", { enumerable: true, get: function () { return userManagement_1.adminChangePassword; } });
Object.defineProperty(exports, "adminDeleteUser", { enumerable: true, get: function () { return userManagement_1.adminDeleteUser; } });
Object.defineProperty(exports, "adminUpdateUserModules", { enumerable: true, get: function () { return userManagement_1.adminUpdateUserModules; } });
Object.defineProperty(exports, "adminUpdateAllowedCollaborators", { enumerable: true, get: function () { return userManagement_1.adminUpdateAllowedCollaborators; } });
var gcpBilling_1 = require("./modules/admin/gcpBilling");
Object.defineProperty(exports, "getGcpMonthlyCost", { enumerable: true, get: function () { return gcpBilling_1.getGcpMonthlyCost; } });
// Tech Events & Walk-ins
var techEvents_1 = require("./modules/events/techEvents");
Object.defineProperty(exports, "fetchUserTechEvents", { enumerable: true, get: function () { return techEvents_1.fetchUserTechEvents; } });
Object.defineProperty(exports, "fetchUserTechEventsTrigger", { enumerable: true, get: function () { return techEvents_1.fetchUserTechEventsTrigger; } });
var walkinDrives_1 = require("./modules/events/walkinDrives");
Object.defineProperty(exports, "fetchUserWalkIns", { enumerable: true, get: function () { return walkinDrives_1.fetchUserWalkIns; } });
Object.defineProperty(exports, "fetchUserWalkInDrives", { enumerable: true, get: function () { return walkinDrives_1.fetchUserWalkInDrives; } });
Object.defineProperty(exports, "fetchUserWalkInsTrigger", { enumerable: true, get: function () { return walkinDrives_1.fetchUserWalkInsTrigger; } });
// Voice Assistant
var voiceAssistant_1 = require("./modules/voice/voiceAssistant");
Object.defineProperty(exports, "voiceAssistantQuery", { enumerable: true, get: function () { return voiceAssistant_1.voiceAssistantQuery; } });
// Job Assistant
var jobPosterAI_1 = require("./modules/job_assistant/jobPosterAI");
Object.defineProperty(exports, "parseJobPostersWithAI", { enumerable: true, get: function () { return jobPosterAI_1.parseJobPostersWithAI; } });
var coverLetterAI_1 = require("./modules/job_assistant/coverLetterAI");
Object.defineProperty(exports, "generateManualJobApplicationWithAI", { enumerable: true, get: function () { return coverLetterAI_1.generateManualJobApplicationWithAI; } });
Object.defineProperty(exports, "refineCoverLetterWithAI", { enumerable: true, get: function () { return coverLetterAI_1.refineCoverLetterWithAI; } });
var emailSender_1 = require("./modules/job_assistant/emailSender");
Object.defineProperty(exports, "sendJobApplicationEmail", { enumerable: true, get: function () { return emailSender_1.sendJobApplicationEmail; } });
var jobDiscoveryAI_1 = require("./modules/job_assistant/jobDiscoveryAI");
Object.defineProperty(exports, "triggerAutoJobDiscoveryAndApply", { enumerable: true, get: function () { return jobDiscoveryAI_1.triggerAutoJobDiscoveryAndApply; } });
// Consolidated Master Schedulers
var masterSchedulers_1 = require("./schedulers/masterSchedulers");
Object.defineProperty(exports, "masterMinuteRunner", { enumerable: true, get: function () { return masterSchedulers_1.masterMinuteRunner; } });
Object.defineProperty(exports, "masterHalfHourlyRunner", { enumerable: true, get: function () { return masterSchedulers_1.masterHalfHourlyRunner; } });
//# sourceMappingURL=index.js.map