"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateAtsResumePdf = generateAtsResumePdf;
const PDFDocument = require("pdfkit");
/**
 * Internal single-pass renderer for a given layout configuration.
 */
function renderResumePass(data, config) {
    return new Promise((resolve, reject) => {
        try {
            const doc = new PDFDocument({
                size: "A4",
                margins: config.margins,
                bufferPages: true
            });
            let pageCount = 1;
            doc.on("pageAdded", () => {
                pageCount++;
            });
            const buffers = [];
            doc.on("data", (chunk) => buffers.push(chunk));
            doc.on("end", () => {
                resolve({
                    buffer: Buffer.concat(buffers),
                    pageCount,
                    lastY: doc.y
                });
            });
            const pageWidth = 595.28;
            const contentWidth = pageWidth - (config.margins.left + config.margins.right);
            const { bodySize, lineGap, bulletGap, spaceFactor } = config;
            // 1. Header (Name & Contact Line)
            doc.fontSize(config.nameSize)
                .font("Helvetica-Bold")
                .fillColor("#111827")
                .text((data.fullName || "Candidate").toUpperCase(), { align: "center" });
            doc.moveDown(0.2 * spaceFactor);
            doc.fontSize(config.contactSize)
                .font("Helvetica")
                .fillColor("#4B5563")
                .text(data.contactLine || "", { align: "center" });
            doc.moveDown(0.4 * spaceFactor);
            function addSectionHeader(title) {
                doc.moveDown(0.3 * spaceFactor);
                const headerY = doc.y;
                doc.fontSize(config.headerSize)
                    .font("Helvetica-Bold")
                    .fillColor("#111827")
                    .text(title.toUpperCase(), config.margins.left, headerY, { width: contentWidth });
                const lineY = doc.y + 2;
                doc.moveTo(config.margins.left, lineY)
                    .lineTo(pageWidth - config.margins.right, lineY)
                    .lineWidth(0.75)
                    .strokeColor("#9CA3AF")
                    .stroke();
                doc.y = lineY + (4 * spaceFactor);
                doc.x = config.margins.left;
            }
            // 2. Professional Summary
            if (data.professionalSummary && data.professionalSummary.trim().length > 0) {
                addSectionHeader("Professional Summary");
                doc.fontSize(bodySize)
                    .font("Helvetica")
                    .fillColor("#374151")
                    .text(data.professionalSummary.trim(), config.margins.left, doc.y, {
                    lineGap,
                    width: contentWidth,
                    align: "left"
                });
                doc.x = config.margins.left;
            }
            // 3. Technical Skills
            if (Array.isArray(data.skills) && data.skills.length > 0) {
                addSectionHeader("Technical Skills");
                for (const s of data.skills) {
                    if (!s.category || !s.items)
                        continue;
                    doc.fontSize(bodySize)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(`${s.category}: `, config.margins.left, doc.y, { continued: true, lineGap })
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text(s.items, { lineGap, width: contentWidth });
                    doc.x = config.margins.left;
                }
            }
            // 4. Professional Experience
            if (Array.isArray(data.experience) && data.experience.length > 0) {
                addSectionHeader("Professional Experience");
                for (const exp of data.experience) {
                    doc.moveDown(0.18 * spaceFactor);
                    const topY = doc.y;
                    doc.fontSize(bodySize + 0.5)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(exp.company || "Company", config.margins.left, topY);
                    doc.fontSize(bodySize)
                        .font("Helvetica-Oblique")
                        .fillColor("#4B5563")
                        .text(exp.period || "", config.margins.left, topY, { align: "right", width: contentWidth });
                    doc.moveDown(0.1 * spaceFactor);
                    const subY = doc.y;
                    doc.fontSize(bodySize)
                        .font("Helvetica-Bold")
                        .fillColor("#374151")
                        .text(exp.role || "Role", config.margins.left, subY);
                    if (exp.location) {
                        doc.fontSize(bodySize)
                            .font("Helvetica")
                            .fillColor("#6B7280")
                            .text(exp.location, config.margins.left, subY, { align: "right", width: contentWidth });
                    }
                    doc.moveDown(0.18 * spaceFactor);
                    if (Array.isArray(exp.bulletPoints)) {
                        for (const bp of exp.bulletPoints) {
                            if (!bp || bp.trim().length === 0)
                                continue;
                            doc.fontSize(bodySize)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•   " + bp.trim(), config.margins.left + 10, doc.y, {
                                indent: -10,
                                lineGap: bulletGap,
                                width: contentWidth - 10
                            });
                            doc.moveDown(0.08 * spaceFactor);
                        }
                    }
                    doc.x = config.margins.left;
                }
            }
            // 5. Key Projects
            if (Array.isArray(data.projects) && data.projects.length > 0) {
                addSectionHeader("Key Projects");
                for (const proj of data.projects) {
                    doc.moveDown(0.18 * spaceFactor);
                    const projY = doc.y;
                    doc.fontSize(bodySize + 0.5)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(proj.title || "Project", config.margins.left, projY, { continued: !!proj.techStack });
                    if (proj.techStack) {
                        doc.font("Helvetica-Oblique")
                            .fillColor("#4B5563")
                            .text("  |  " + proj.techStack, { lineGap, width: contentWidth });
                    }
                    doc.moveDown(0.14 * spaceFactor);
                    if (Array.isArray(proj.bulletPoints)) {
                        for (const bp of proj.bulletPoints) {
                            if (!bp || bp.trim().length === 0)
                                continue;
                            doc.fontSize(bodySize)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•   " + bp.trim(), config.margins.left + 10, doc.y, {
                                indent: -10,
                                lineGap: bulletGap,
                                width: contentWidth - 10
                            });
                            doc.moveDown(0.08 * spaceFactor);
                        }
                    }
                    doc.x = config.margins.left;
                }
            }
            // 6. Education
            if (Array.isArray(data.education) && data.education.length > 0) {
                addSectionHeader("Education");
                for (const edu of data.education) {
                    doc.moveDown(0.15 * spaceFactor);
                    const ey = doc.y;
                    doc.fontSize(bodySize)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(edu.degree || "Degree", config.margins.left, ey);
                    doc.fontSize(bodySize)
                        .font("Helvetica")
                        .fillColor("#4B5563")
                        .text(edu.period || "", config.margins.left, ey, { align: "right", width: contentWidth });
                    doc.moveDown(0.08 * spaceFactor);
                    const instLoc = edu.institution + (edu.location ? ", " + edu.location : "");
                    doc.fontSize(bodySize)
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text(instLoc, config.margins.left, doc.y, { lineGap, width: contentWidth });
                    doc.x = config.margins.left;
                }
            }
            // 7. Certifications (if any)
            if (Array.isArray(data.certifications) && data.certifications.length > 0) {
                addSectionHeader("Certifications");
                for (const cert of data.certifications) {
                    if (!cert || cert.trim().length === 0)
                        continue;
                    doc.fontSize(bodySize)
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text("•   " + cert.trim(), config.margins.left + 10, doc.y, {
                        indent: -10,
                        lineGap: bulletGap,
                        width: contentWidth - 10
                    });
                    doc.moveDown(0.08 * spaceFactor);
                }
                doc.x = config.margins.left;
            }
            doc.end();
        }
        catch (err) {
            reject(err);
        }
    });
}
/**
 * Generates an ATS-compliant, elegantly formatted PDF resume with smart adaptive page fitting.
 * Follows the standard Jake's Resume / Ivy League format:
 * - Pure vector text (100% selectable by ATS scanners)
 * - Standard fonts: Helvetica, Helvetica-Bold, Helvetica-Oblique
 * - Section headers with clean dividers
 * - Intelligent anti-spillover engine: If 1-5 lines spill awkwardly onto Page 2, automatically
 *   compacts spacing so the resume fits into exactly 1 clean page.
 * - Anti-stub engine: If content fills less than half a page, gracefully expands spacing
 *   so the resume occupies the page proportionately.
 * - Genuine 2-page resumes with substantial multi-year history are fully supported.
 */
async function generateAtsResumePdf(data) {
    // 1. Standard Layout Pass
    const standard = await renderResumePass(data, {
        margins: { top: 36, bottom: 36, left: 36, right: 36 },
        nameSize: 16,
        contactSize: 8.5,
        headerSize: 10,
        bodySize: 8.5,
        lineGap: 1.5,
        bulletGap: 1.6,
        spaceFactor: 1.0
    });
    // Case A: Awkward Spillover onto Page 2 (lastY < 260pt on page 2, i.e. 1 to 5 orphan lines)
    if (standard.pageCount === 2 && standard.lastY < 260) {
        console.log(`[ResumePDF] Minor spillover detected onto Page 2 (lastY: ${standard.lastY.toFixed(1)}pt). Optimizing into 1 page...`);
        const compact = await renderResumePass(data, {
            margins: { top: 26, bottom: 26, left: 30, right: 30 },
            nameSize: 15,
            contactSize: 8.0,
            headerSize: 9.5,
            bodySize: 8.0,
            lineGap: 1.0,
            bulletGap: 1.1,
            spaceFactor: 0.72
        });
        if (compact.pageCount === 1) {
            console.log(`[ResumePDF] Successfully condensed resume into 1 clean page (lastY: ${compact.lastY.toFixed(1)}pt).`);
            return compact.buffer;
        }
        // Tier 3: Tight 1-Page Layout if still barely overflowing
        if (compact.pageCount === 2 && compact.lastY < 80) {
            const tight = await renderResumePass(data, {
                margins: { top: 22, bottom: 22, left: 26, right: 26 },
                nameSize: 14,
                contactSize: 7.8,
                headerSize: 9.0,
                bodySize: 7.7,
                lineGap: 0.8,
                bulletGap: 0.9,
                spaceFactor: 0.62
            });
            if (tight.pageCount === 1) {
                console.log(`[ResumePDF] Successfully condensed resume into 1 page via tight layout (lastY: ${tight.lastY.toFixed(1)}pt).`);
                return tight.buffer;
            }
        }
    }
    // Case B: Content is on 1 page but sparse / "half page" (< 460pt filled out of 805pt printable area)
    if (standard.pageCount === 1 && standard.lastY < 460) {
        console.log(`[ResumePDF] Half-page sparse content detected (lastY: ${standard.lastY.toFixed(1)}pt). Expanding layout gracefully...`);
        const expanded = await renderResumePass(data, {
            margins: { top: 38, bottom: 38, left: 36, right: 36 },
            nameSize: 17,
            contactSize: 9.0,
            headerSize: 10.5,
            bodySize: 9.0,
            lineGap: 2.1,
            bulletGap: 2.2,
            spaceFactor: 1.25
        });
        if (expanded.pageCount === 1) {
            console.log(`[ResumePDF] Gracefully expanded 1-page layout to fill page (new lastY: ${expanded.lastY.toFixed(1)}pt).`);
            return expanded.buffer;
        }
    }
    return standard.buffer;
}
//# sourceMappingURL=pdfResumeGenerator.js.map