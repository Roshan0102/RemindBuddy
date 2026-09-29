"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateAtsResumePdf = generateAtsResumePdf;
const PDFDocument = require("pdfkit");
/**
 * Generates an ATS-compliant, elegantly formatted PDF resume.
 * Follows the standard Jake's Resume / Ivy League format:
 * - 0.5 in margins, pure vector text (selectable by ATS scanners)
 * - Standard fonts: Helvetica, Helvetica-Bold, Helvetica-Oblique
 * - Clean section headers with horizontal dividers
 * - Responsive 1 or 2 page flow depending on candidate history
 */
function generateAtsResumePdf(data) {
    return new Promise((resolve, reject) => {
        try {
            const doc = new PDFDocument({
                size: "A4",
                margins: { top: 36, bottom: 36, left: 36, right: 36 },
                bufferPages: true
            });
            const buffers = [];
            doc.on("data", (chunk) => buffers.push(chunk));
            doc.on("end", () => resolve(Buffer.concat(buffers)));
            const pageWidth = 595.28;
            const contentWidth = pageWidth - 72; // 523.28pt printable width
            // 1. Header (Name & Contact Line)
            doc.fontSize(16)
                .font("Helvetica-Bold")
                .fillColor("#111827")
                .text((data.fullName || "Candidate").toUpperCase(), { align: "center" });
            doc.moveDown(0.2);
            doc.fontSize(8.5)
                .font("Helvetica")
                .fillColor("#4B5563")
                .text(data.contactLine || "", { align: "center" });
            doc.moveDown(0.5);
            function addSectionHeader(title) {
                doc.moveDown(0.35);
                const headerY = doc.y;
                doc.fontSize(10)
                    .font("Helvetica-Bold")
                    .fillColor("#111827")
                    .text(title.toUpperCase(), 36, headerY, { width: contentWidth });
                const lineY = doc.y + 2;
                doc.moveTo(36, lineY)
                    .lineTo(pageWidth - 36, lineY)
                    .lineWidth(0.75)
                    .strokeColor("#9CA3AF")
                    .stroke();
                // Clean 5pt breathing room between line and content, reset left margin
                doc.y = lineY + 5;
                doc.x = 36;
            }
            // 2. Professional Summary
            if (data.professionalSummary && data.professionalSummary.trim().length > 0) {
                addSectionHeader("Professional Summary");
                doc.fontSize(8.5)
                    .font("Helvetica")
                    .fillColor("#374151")
                    .text(data.professionalSummary.trim(), 36, doc.y, { lineGap: 1.5, width: contentWidth, align: "left" });
                doc.x = 36;
            }
            // 3. Technical Skills
            if (Array.isArray(data.skills) && data.skills.length > 0) {
                addSectionHeader("Technical Skills");
                for (const s of data.skills) {
                    if (!s.category || !s.items)
                        continue;
                    doc.fontSize(8.5)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(`${s.category}: `, 36, doc.y, { continued: true, lineGap: 1.5 })
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text(s.items, { lineGap: 1.5, width: contentWidth });
                    doc.x = 36;
                }
            }
            // 4. Professional Experience
            if (Array.isArray(data.experience) && data.experience.length > 0) {
                addSectionHeader("Professional Experience");
                for (const exp of data.experience) {
                    doc.moveDown(0.2);
                    const topY = doc.y;
                    doc.fontSize(9)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(exp.company || "Company", 36, topY);
                    doc.fontSize(8.5)
                        .font("Helvetica-Oblique")
                        .fillColor("#4B5563")
                        .text(exp.period || "", 36, topY, { align: "right", width: contentWidth });
                    doc.moveDown(0.12);
                    const subY = doc.y;
                    doc.fontSize(8.5)
                        .font("Helvetica-Bold")
                        .fillColor("#374151")
                        .text(exp.role || "Role", 36, subY);
                    if (exp.location) {
                        doc.fontSize(8.5)
                            .font("Helvetica")
                            .fillColor("#6B7280")
                            .text(exp.location, 36, subY, { align: "right", width: contentWidth });
                    }
                    doc.moveDown(0.2);
                    if (Array.isArray(exp.bulletPoints)) {
                        for (const bp of exp.bulletPoints) {
                            if (!bp || bp.trim().length === 0)
                                continue;
                            doc.fontSize(8.5)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•   " + bp.trim(), 46, doc.y, {
                                indent: -10,
                                lineGap: 1.6,
                                width: contentWidth - 10
                            });
                            doc.moveDown(0.1);
                        }
                    }
                    doc.x = 36;
                }
            }
            // 5. Key Projects
            if (Array.isArray(data.projects) && data.projects.length > 0) {
                addSectionHeader("Key Projects");
                for (const proj of data.projects) {
                    doc.moveDown(0.2);
                    const projY = doc.y;
                    doc.fontSize(9)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(proj.title || "Project", 36, projY, { continued: !!proj.techStack });
                    if (proj.techStack) {
                        doc.font("Helvetica-Oblique")
                            .fillColor("#4B5563")
                            .text("  |  " + proj.techStack, { lineGap: 1.5, width: contentWidth });
                    }
                    doc.moveDown(0.15);
                    if (Array.isArray(proj.bulletPoints)) {
                        for (const bp of proj.bulletPoints) {
                            if (!bp || bp.trim().length === 0)
                                continue;
                            doc.fontSize(8.5)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•   " + bp.trim(), 46, doc.y, {
                                indent: -10,
                                lineGap: 1.6,
                                width: contentWidth - 10
                            });
                            doc.moveDown(0.1);
                        }
                    }
                    doc.x = 36;
                }
            }
            // 6. Education
            if (Array.isArray(data.education) && data.education.length > 0) {
                addSectionHeader("Education");
                for (const edu of data.education) {
                    doc.moveDown(0.15);
                    const ey = doc.y;
                    doc.fontSize(8.5)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(edu.degree || "Degree", 36, ey);
                    doc.fontSize(8.5)
                        .font("Helvetica")
                        .fillColor("#4B5563")
                        .text(edu.period || "", 36, ey, { align: "right", width: contentWidth });
                    doc.moveDown(0.1);
                    const instLoc = edu.institution + (edu.location ? ", " + edu.location : "");
                    doc.fontSize(8.5)
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text(instLoc, 36, doc.y, { lineGap: 1.5, width: contentWidth });
                    doc.x = 36;
                }
            }
            // 7. Certifications (if any)
            if (Array.isArray(data.certifications) && data.certifications.length > 0) {
                addSectionHeader("Certifications");
                for (const cert of data.certifications) {
                    if (!cert || cert.trim().length === 0)
                        continue;
                    doc.fontSize(8.5)
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text("•   " + cert.trim(), 46, doc.y, {
                        indent: -10,
                        lineGap: 1.6,
                        width: contentWidth - 10
                    });
                    doc.moveDown(0.1);
                }
                doc.x = 36;
            }
            doc.end();
        }
        catch (err) {
            reject(err);
        }
    });
}
//# sourceMappingURL=pdfResumeGenerator.js.map