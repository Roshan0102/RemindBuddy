"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.formatEmailContent = formatEmailContent;
/**
 * Converts a markdown-formatted cover letter or pitch into clean, professional HTML
 * and also produces a clean plain-text version without markdown asterisks.
 */
function formatEmailContent(rawMarkdownText) {
    if (!rawMarkdownText) {
        return { html: "", text: "" };
    }
    // 1. Clean plain text fallback: strip **bold** or *italic* asterisks
    const cleanPlainText = rawMarkdownText
        .replace(/\*\*(.*?)\*\*/g, '$1')
        .replace(/\*(.*?)\*/g, '$1')
        .replace(/__(.*?)__/g, '$1')
        .replace(/_(.*?)_/g, '$1');
    // 2. Generate clean, responsive HTML for email clients (Gmail, Outlook, Apple Mail)
    const lines = rawMarkdownText.split('\n');
    let htmlBody = '';
    for (let i = 0; i < lines.length; i++) {
        let line = lines[i];
        // Escape basic HTML characters
        line = line
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
        // Bold: **text** or __text__
        line = line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        line = line.replace(/__(.*?)__/g, '<strong>$1</strong>');
        // Italic: *text* or _text_
        line = line.replace(/\*(.*?)\*/g, '<em>$1</em>');
        line = line.replace(/_(.*?)_/g, '<em>$1</em>');
        const trimmed = line.trim();
        if (trimmed === '') {
            htmlBody += '<div style="height: 12px;"></div>';
        }
        else if (trimmed.startsWith('•') || trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
            htmlBody += `<div style="margin-bottom: 6px; padding-left: 14px; line-height: 1.6;">${line}</div>`;
        }
        else {
            htmlBody += `<div style="margin-bottom: 6px; line-height: 1.6;">${line}</div>`;
        }
    }
    const html = `
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.6; color: #1e293b; margin: 0; padding: 0; }
strong { font-weight: 600; color: #0f172a; }
</style>
</head>
<body>
${htmlBody}
</body>
</html>`.trim();
    return { html, text: cleanPlainText };
}
//# sourceMappingURL=emailFormatter.js.map