"use strict";
/**
 * Utility for strict, deterministic candidate experience matching against job posts and descriptions.
 * Prevents unwanted applications to senior / 5+ / 5-8 year positions when candidate is junior/entry-level.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.isExperienceExceeded = isExperienceExceeded;
/**
 * Evaluates whether a job post's stated experience requirement exceeds the candidate's maximum experience.
 *
 * @param content Full text of the job description or LinkedIn post
 * @param maxExp Candidate's configured maximum experience in years (e.g., 2)
 * @param minExp Candidate's configured minimum experience in years (e.g., 0)
 */
function isExperienceExceeded(content, maxExp, minExp = 0) {
    const textLower = (content || "").toLowerCase();
    if (!textLower)
        return { exceeded: false };
    // 1. Senior / Lead / Principal leadership titles (Disqualify if candidate maxExp <= 4)
    if (maxExp <= 4) {
        const seniorTitles = [
            "principal", "staff engineer", "engineering manager", "director", "architect",
            "tech lead", "technical lead", "team lead", "lead devops", "lead engineer",
            "lead cloud", "lead sre", "lead developer", "lead infrastructure",
            "senior devops", "senior cloud", "senior sre", "senior site reliability",
            "sr. devops", "sr devops", "sr. cloud", "sr cloud", "sr. sre", "sr sre",
            "sr. engineer", "sr engineer", "sr. software", "sr software"
        ];
        for (const title of seniorTitles) {
            const regex = new RegExp(`\\b${title.replace('.', '\\.')}\\b`, 'i');
            if (regex.test(textLower)) {
                return {
                    exceeded: true,
                    reason: `Role requires senior seniority level ("${title}") exceeding candidate's max experience of ${maxExp} years.`,
                    detectedText: title
                };
            }
        }
    }
    // Maximum allowed minimum threshold: candidate maxExp + 1 year stretch (or at least 2)
    // E.g. If candidate has 2 years, we allow jobs requiring up to 3 years max, but REJECT jobs requiring 4, 5, 5-8, 6+, etc.
    const maxAllowedMinYears = Math.max(maxExp + 1, 2);
    // 2. Experience range: e.g. "5 to 8 years", "5-8 years", "5 - 8 yrs", "5 to 8 Yrs", "4 to 7 years", "6-10 years"
    const rangeRegex = /(\d+)\s*(?:-|to)\s*(\d+)\s*(?:years?|yrs?)/gi;
    let match;
    while ((match = rangeRegex.exec(textLower)) !== null) {
        const minYears = parseInt(match[1], 10);
        if (minYears > maxAllowedMinYears) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}" which exceeds candidate's max of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    // 3. Plus notation: e.g. "5+ years", "5+ yrs", "4 + years", "6+ years"
    const plusRegex = /(\d+)\s*\+\s*(?:years?|yrs?)/gi;
    while ((match = plusRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (years > maxAllowedMinYears) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}" which exceeds candidate's max of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    // 4. Minimum phrasing: e.g. "min 5 years", "minimum 5 years", "at least 5 years", "min 4 yrs"
    const minRegex = /(?:min(?:imum)?|at least)\s*(\d+)\s*(?:years?|yrs?)/gi;
    while ((match = minRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (years > maxAllowedMinYears) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}" which exceeds candidate's max of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    // 5. Generic "X years of experience" / "X yrs exp"
    const genericRegex = /(\d+)\s*(?:years?|yrs?)\s*(?:of\s*)?exp/gi;
    while ((match = genericRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (years > maxAllowedMinYears) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}" which exceeds candidate's max of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    return { exceeded: false };
}
//# sourceMappingURL=experienceMatcher.js.map