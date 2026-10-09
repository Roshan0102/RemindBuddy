"use strict";
/**
 * Utility for strict, deterministic candidate experience matching against job posts and descriptions.
 * Universally generalized for all users, careers, and experience levels.
 * Prevents unmatched applications to senior / 5+ / 3-6 year positions when candidate does not qualify.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.isExperienceExceeded = isExperienceExceeded;
/**
 * Evaluates whether a job post's stated experience requirement exceeds the candidate's experience profile.
 *
 * @param content Full text of the job description or posting
 * @param maxExp Candidate's configured maximum experience in years (e.g., 2, 3)
 * @param minExp Candidate's configured minimum experience in years (e.g., 0, 1)
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
            "sr. engineer", "sr engineer", "sr. software", "sr software", "vp engineering",
            "head of engineering", "head of infrastructure"
        ];
        for (const title of seniorTitles) {
            const regex = new RegExp(`\\b${title.replace(/\./g, "\\.")}\\b`, "i");
            if (regex.test(textLower)) {
                return {
                    exceeded: true,
                    reason: `Role requires senior seniority level ("${title}") exceeding candidate's max experience of ${maxExp} years.`,
                    detectedText: title
                };
            }
        }
    }
    /**
     * Determines whether a minimum experience baseline floor (e.g. "3+ years", "minimum of 3 years")
     * exceeds what a candidate in range [minExp, maxExp] satisfies.
     */
    function isFloorExceeded(threshold) {
        // If required floor exceeds candidate's upper limit, always exceeded
        if (threshold > maxExp)
            return true;
        // If required floor equals or exceeds candidate maxExp while candidate's experience starts lower
        // (e.g. a job requiring 3+ or min 3 years requires 3 as floor; a 1-3y candidate has not yet achieved 3+ years)
        if (threshold >= maxExp && minExp < maxExp)
            return true;
        return false;
    }
    // 2. Experience range: e.g. "3-6 years", "3–6 years" (en-dash), "3—6 years" (em-dash), "5 to 8 years", "5 - 8 yrs"
    // Handles ASCII hyphen, Unicode en-dash (\u2013), em-dash (\u2014), and "to"
    const rangeRegex = /(\d+)\s*(?:[-–—]|to)\s*(\d+)\s*(?:years?|yrs?)/gi;
    let match;
    while ((match = rangeRegex.exec(textLower)) !== null) {
        const lowYears = parseInt(match[1], 10);
        const highYears = parseInt(match[2], 10);
        // Disqualify if lower bound exceeds candidate maxExp (e.g. 4-7 yrs for max 3 yrs)
        // OR if the range is a higher tier spanning beyond candidate maxExp (e.g. 3-6 yrs for candidate with max 3 yrs)
        if (lowYears > maxExp || (lowYears >= maxExp && highYears > maxExp)) {
            return {
                exceeded: true,
                reason: `Job requires "${match[0]}" (${lowYears}-${highYears} yrs), exceeding candidate's target range (${minExp}-${maxExp} yrs).`,
                detectedText: match[0]
            };
        }
    }
    // 3. Plus notation: e.g. "8+ years", "5+ yrs", "4 + years", "3+ years"
    const plusRegex = /(\d+)\s*\+\s*(?:years?|yrs?)/gi;
    while ((match = plusRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (isFloorExceeded(years)) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}", exceeding candidate's max experience of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    // 4. "Above X years", "over X years", "more than X years", "greater than X years"
    const aboveRegex = /(?:above|over|more than|greater than)\s*(\d+)\s*(?:years?|yrs?)/gi;
    while ((match = aboveRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (isFloorExceeded(years) || years >= maxExp) {
            return {
                exceeded: true,
                reason: `Job requires "${match[0]}", exceeding candidate's experience range (${minExp}-${maxExp} yrs).`,
                detectedText: match[0]
            };
        }
    }
    // 5. "X years and above", "X years or more"
    const andAboveRegex = /(\d+)\s*(?:years?|yrs?)\s*(?:and above|or more)/gi;
    while ((match = andAboveRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (isFloorExceeded(years) || years >= maxExp) {
            return {
                exceeded: true,
                reason: `Job requires "${match[0]}", exceeding candidate's experience range (${minExp}-${maxExp} yrs).`,
                detectedText: match[0]
            };
        }
    }
    // 6. Minimum phrasing: e.g. "minimum of 3 years", "minimum 5 years", "at least 4 years", "min. 3 yrs"
    const minRegex = /(?:min(?:imum)?(?:\s+of)?|at least)\s*(\d+)\s*(?:years?|yrs?)/gi;
    while ((match = minRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (isFloorExceeded(years)) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}", exceeding candidate's experience range (${minExp}-${maxExp} yrs).`,
                detectedText: match[0]
            };
        }
    }
    // 7. Generic "X years of experience" / "X yrs exp"
    const genericRegex = /(\d+)\s*(?:years?|yrs?)\s*(?:of\s*)?exp(?:erience)?/gi;
    while ((match = genericRegex.exec(textLower)) !== null) {
        const years = parseInt(match[1], 10);
        if (isFloorExceeded(years)) {
            return {
                exceeded: true,
                reason: `Job explicitly requires "${match[0]}", exceeding candidate's max of ${maxExp} years.`,
                detectedText: match[0]
            };
        }
    }
    return { exceeded: false };
}
//# sourceMappingURL=experienceMatcher.js.map