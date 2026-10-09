package com.expdeath.coach.models

import com.expdeath.coach.stats.Stats

/** Account state `weeklyReview` — the Sunday AI review (shared with the web). */
data class WeeklyReviewCache(val week: String, val at: Double, val text: String, val count: Int, val progressions: String) {
    fun toJson(): JSONValue = jobj {
        put("week", week); put("at", at); put("text", text); put("count", count); put("progressions", progressions)
    }

    companion object {
        fun fromJson(v: JSONValue): WeeklyReviewCache? {
            val c = v.obj ?: return null
            return WeeklyReviewCache(
                week = c.lenientString("week") ?: return null,
                at = c.lenientDouble("at") ?: 0.0,
                text = c.lenientString("text") ?: return null,
                count = c.lenientInt("count") ?: 0,
                progressions = c.lenientString("progressions") ?: "",
            )
        }
    }
}

/** Account state `monthlyReport` — the new-month AI report. */
data class MonthlyReportCache(val month: String, val at: Double, val text: String, val sum: Stats.MonthSummary) {
    fun toJson(): JSONValue = jobj { put("month", month); put("at", at); put("text", text); put("sum", sum.toJson()) }

    companion object {
        fun fromJson(v: JSONValue): MonthlyReportCache? {
            val c = v.obj ?: return null
            return MonthlyReportCache(
                month = c.lenientString("month") ?: return null,
                at = c.lenientDouble("at") ?: 0.0,
                text = c.lenientString("text") ?: return null,
                sum = c.lenient("sum", Stats.MonthSummary::fromJson) ?: return null,
            )
        }
    }
}
