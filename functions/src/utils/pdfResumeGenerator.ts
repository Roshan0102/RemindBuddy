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

/**
 * Generates an ATS-compliant, elegantly formatted PDF resume.
 * Follows the standard Jake's Resume / Ivy League format:
 * - 0.5 in margins, pure vector text (selectable by ATS scanners)
 * - Standard fonts: Helvetica, Helvetica-Bold, Helvetica-Oblique
 * - Clean section headers with horizontal dividers
 * - Responsive 1 or 2 page flow depending on candidate history
 */
export function generateAtsResumePdf(data: TailoredResumeData): Promise<Buffer> {
    return new Promise((resolve, reject) => {
        try {
            const doc = new PDFDocument({
                size: "A4",
                margins: { top: 36, bottom: 36, left: 36, right: 36 },
                bufferPages: true
            });

            const buffers: Buffer[] = [];
            doc.on("data", (chunk: Buffer) => buffers.push(chunk));
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

            function addSectionHeader(title: string) {
                doc.moveDown(0.35);
                doc.fontSize(10)
                    .font("Helvetica-Bold")
                    .fillColor("#1F2937")
                    .text(title.toUpperCase());

                const y = doc.y;
                doc.moveTo(36, y)
                    .lineTo(pageWidth - 36, y)
                    .lineWidth(0.6)
                    .strokeColor("#9CA3AF")
                    .stroke();

                doc.moveDown(0.25);
            }

            // 2. Professional Summary
            if (data.professionalSummary && data.professionalSummary.trim().length > 0) {
                addSectionHeader("Professional Summary");
                doc.fontSize(8.5)
                    .font("Helvetica")
                    .fillColor("#374151")
                    .text(data.professionalSummary.trim(), { lineGap: 1.5, align: "left" });
            }

            // 3. Technical Skills
            if (Array.isArray(data.skills) && data.skills.length > 0) {
                addSectionHeader("Technical Skills");
                for (const s of data.skills) {
                    if (!s.category || !s.items) continue;
                    doc.fontSize(8.5)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(`${s.category}: `, { continued: true })
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text(s.items, { lineGap: 1.5 });
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

                    doc.moveDown(0.15);
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

                    doc.moveDown(0.25);

                    if (Array.isArray(exp.bulletPoints)) {
                        for (const bp of exp.bulletPoints) {
                            if (!bp || bp.trim().length === 0) continue;
                            doc.fontSize(8.5)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•  " + bp.trim(), 48, doc.y, { lineGap: 1.5, width: contentWidth - 12 });
                            doc.moveDown(0.12);
                        }
                    }
                }
            }

            // 5. Key Projects
            if (Array.isArray(data.projects) && data.projects.length > 0) {
                addSectionHeader("Key Projects");
                for (const proj of data.projects) {
                    doc.moveDown(0.2);
                    doc.fontSize(9)
                        .font("Helvetica-Bold")
                        .fillColor("#111827")
                        .text(proj.title || "Project", { continued: !!proj.techStack });

                    if (proj.techStack) {
                        doc.font("Helvetica-Oblique")
                            .fillColor("#4B5563")
                            .text("  |  " + proj.techStack);
                    }

                    doc.moveDown(0.15);

                    if (Array.isArray(proj.bulletPoints)) {
                        for (const bp of proj.bulletPoints) {
                            if (!bp || bp.trim().length === 0) continue;
                            doc.fontSize(8.5)
                                .font("Helvetica")
                                .fillColor("#374151")
                                .text("•  " + bp.trim(), 48, doc.y, { lineGap: 1.5, width: contentWidth - 12 });
                            doc.moveDown(0.12);
                        }
                    }
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
                        .text(instLoc);
                }
            }

            // 7. Certifications (if any)
            if (Array.isArray(data.certifications) && data.certifications.length > 0) {
                addSectionHeader("Certifications");
                for (const cert of data.certifications) {
                    if (!cert || cert.trim().length === 0) continue;
                    doc.fontSize(8.5)
                        .font("Helvetica")
                        .fillColor("#374151")
                        .text("•  " + cert.trim(), 48, doc.y, { lineGap: 1.5, width: contentWidth - 12 });
                    doc.moveDown(0.1);
                }
            }

            doc.end();
        } catch (err) {
            reject(err);
        }
    });
}
