import PDFDocument = require("pdfkit");

export interface ResumeSkillCategory {
    category: string;
    items: string;
}

export interface ResumeExperienceItem {
    company: string;
    role: string;
    period: string;
    location?: string;
    bulletPoints: string[];
}

export interface ResumeProjectItem {
    title: string;
    techStack?: string;
    bulletPoints: string[];
}

export interface ResumeEducationItem {
    degree: string;
    institution: string;
    period: string;
    location?: string;
}

export interface TailoredResumeData {
    fullName: string;
    contactLine: string;
    professionalSummary?: string;
    skills?: ResumeSkillCategory[];
    experience?: ResumeExperienceItem[];
    projects?: ResumeProjectItem[];
    education?: ResumeEducationItem[];
    certifications?: string[];
}

interface LayoutConfig {
    margins: { top: number; bottom: number; left: number; right: number };
    nameSize: number;
    contactSize: number;
    headerSize: number;
    bodySize: number;
    lineGap: number;
    bulletGap: number;
    spaceFactor: number;
}

/**
 * Render contact line with clickable hyperlinks (email, LinkedIn, GitHub, portfolio)
 * and centered alignment with automatic line wrapping.
 */
function renderClickableContactLine(
    doc: PDFKit.PDFDocument,
    contactLine: string,
    config: LayoutConfig,
    contentWidth: number
): void {
    if (!contactLine || !contactLine.trim()) return;

    doc.fontSize(config.contactSize).font("Helvetica");

    const rawSegments = contactLine.split(/[|•]/).map(s => s.trim()).filter(Boolean);
    const parsedTokens: { text: string; link: string | null }[] = [];

    for (let seg of rawSegments) {
        let label = seg;
        let link: string | null = null;

        // Clean label if format is "Portfolio: https://..." or "LinkedIn: https://..."
        const prefixMatch = seg.match(/^(Portfolio|Website|GitHub|LinkedIn)\s*:\s*(.+)$/i);
        if (prefixMatch) {
            seg = prefixMatch[2].trim();
        }

        const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(seg) || (seg.includes("@") && !seg.includes("http") && !seg.includes("/"));
        const isUrl = /^https?:\/\//i.test(seg) ||
                      /^(www\.)?[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(\/[^\s]*)?$/i.test(seg);

        if (isEmail) {
            const cleanEmail = seg.replace(/^mailto:/i, "").trim();
            label = cleanEmail;
            link = `mailto:${cleanEmail}`;
        } else if (isUrl) {
            const cleanUrl = seg.trim();
            label = cleanUrl.replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "");
            link = cleanUrl.startsWith("http://") || cleanUrl.startsWith("https://")
                ? cleanUrl
                : `https://${cleanUrl}`;
        } else {
            label = seg;
            link = null;
        }

        parsedTokens.push({ text: label, link });
    }

    const sep = " | ";
    const sepWidth = doc.widthOfString(sep);

    // Group into lines that fit within contentWidth
    const lines: { tokens: { text: string; link: string | null }[]; width: number }[] = [];
    let currentLine: { text: string; link: string | null }[] = [];
    let currentLineWidth = 0;

    for (let i = 0; i < parsedTokens.length; i++) {
        const token = parsedTokens[i];
        const tokenWidth = doc.widthOfString(token.text);
        const neededWidth = currentLine.length === 0 ? tokenWidth : currentLineWidth + sepWidth + tokenWidth;

        if (neededWidth <= contentWidth || currentLine.length === 0) {
            currentLine.push(token);
            currentLineWidth = neededWidth;
        } else {
            lines.push({ tokens: currentLine, width: currentLineWidth });
            currentLine = [token];
            currentLineWidth = tokenWidth;
        }
    }
    if (currentLine.length > 0) {
        lines.push({ tokens: currentLine, width: currentLineWidth });
    }

    // Render each line centered
    const lineHeight = doc.currentLineHeight() + 2;
    for (const line of lines) {
        let x = config.margins.left + (contentWidth - line.width) / 2;
        const y = doc.y;

        for (let i = 0; i < line.tokens.length; i++) {
            const token = line.tokens[i];
            const tokenWidth = doc.widthOfString(token.text);

            if (token.link) {
                doc.fillColor("#2563EB")
                   .text(token.text, x, y, { link: token.link, underline: true, lineBreak: false });
            } else {
                doc.fillColor("#4B5563")
                   .text(token.text, x, y, { lineBreak: false });
            }

            x += tokenWidth;

            if (i < line.tokens.length - 1) {
                doc.fillColor("#9CA3AF")
                   .text(sep, x, y, { lineBreak: false });
                x += sepWidth;
            }
        }
        doc.y = y + lineHeight;
    }
    doc.x = config.margins.left;
}

/**
 * Internal single-pass renderer for a given layout configuration.
 */
function renderResumePass(
    data: TailoredResumeData,
    config: LayoutConfig
): Promise<{ buffer: Buffer; pageCount: number; lastY: number }> {
    return new Promise((resolve, reject) => {
        try {
            const doc = new PDFDocument({
                size: "A4",
                margins: config.margins,
                bufferPages: true,
                info: {
                    Title: `${data.fullName || "Candidate"} - Resume`,
                    Author: data.fullName || "Candidate",
                    Subject: "Professional Resume",
                    Keywords: "Resume, CV, Career, Professional Experience",
                    Creator: "Adobe InDesign 19.0 (Macintosh)",
                    Producer: "macOS Quartz PDFContext",
                    ModDate: new Date(),
                    CreationDate: new Date()
                }
            });

            let pageCount = 1;
            doc.on("pageAdded", () => {
                pageCount++;
            });

            const buffers: Buffer[] = [];
            doc.on("data", (chunk: Buffer) => buffers.push(chunk));
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
            renderClickableContactLine(doc, data.contactLine || "", config, contentWidth);
            doc.moveDown(0.3 * spaceFactor);

            function addSectionHeader(title: string) {
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
                    if (!s.category || !s.items) continue;
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
                            if (!bp || bp.trim().length === 0) continue;
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
                            if (!bp || bp.trim().length === 0) continue;
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
                    if (!cert || cert.trim().length === 0) continue;
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
        } catch (err) {
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
export async function generateAtsResumePdf(data: TailoredResumeData): Promise<Buffer> {
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
