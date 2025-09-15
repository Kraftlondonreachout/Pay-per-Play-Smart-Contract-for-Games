;; Game Analytics & Statistics Engine
;; Tracks detailed gameplay metrics and provides insights for the pay-per-play platform

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u2001))
(define-constant ERR-INVALID-INPUT (err u2002))
(define-constant ERR-DATA-NOT-FOUND (err u2003))
(define-constant ERR-ANALYSIS-FAILED (err u2004))

;; Configuration constants
(define-constant MAX-METRICS-PER-GAME u100)
(define-constant ANALYSIS-WINDOW-BLOCKS u1440) ;; 24 hours
(define-constant MIN-GAMES-FOR-TREND u5)

;; Data variables for global settings
(define-data-var metrics-enabled bool true)
(define-data-var analytics-counter uint u0)
(define-data-var retention-period uint u10080) ;; 1 week in blocks

;; Core game session data tracking
(define-map game-sessions
    { session-id: uint }
    {
        player: principal,
        start-time: uint,
        end-time: uint,
        duration: uint,
        score: uint,
        completion-rate: uint,
        difficulty-level: uint,
        game-mode: (string-ascii 20)
    }
)

;; Player behavior patterns and metrics
(define-map player-analytics
    { player: principal }
    {
        total-playtime: uint,
        average-session-duration: uint,
        preferred-game-mode: (string-ascii 20),
        skill-progression: uint,
        engagement-score: uint,
        last-active: uint,
        sessions-this-week: uint,
        best-streak: uint,
        current-streak: uint
    }
)

;; Aggregate game performance metrics
(define-map game-performance-stats
    { time-period: uint }
    {
        total-sessions: uint,
        total-revenue: uint,
        average-session-length: uint,
        player-retention-rate: uint,
        peak-concurrent-users: uint,
        most-popular-mode: (string-ascii 20),
        difficulty-distribution: { easy: uint, medium: uint, hard: uint }
    }
)

;; Detailed behavioral insights
(define-map behavioral-patterns
    { pattern-id: uint }
    {
        player: principal,
        pattern-type: (string-ascii 30),
        frequency: uint,
        last-occurrence: uint,
        confidence-score: uint,
        related-metrics: (list 5 uint)
    }
)

;; Session progression tracking
(define-map session-progression
    { player: principal, session-id: uint }
    {
        checkpoints-reached: uint,
        time-spent-per-level: (list 10 uint),
        deaths-per-level: (list 10 uint),
        items-collected: uint,
        special-actions: uint
    }
)

;; Achievement and milestone analytics
(define-map achievement-analytics
    { achievement-id: uint }
    {
        unlock-rate: uint,
        average-time-to-unlock: uint,
        difficulty-rating: uint,
        player-feedback-score: uint,
        prerequisite-completion: uint
    }
)

;; Revenue and monetization insights
(define-map revenue-analytics
    { time-bucket: uint }
    {
        gross-revenue: uint,
        unique-paying-users: uint,
        average-revenue-per-user: uint,
        conversion-rate: uint,
        churn-rate: uint,
        lifetime-value: uint
    }
)

;; Player segmentation data
(define-map player-segments
    { player: principal }
    {
        segment-type: (string-ascii 20),
        value-score: uint,
        risk-score: uint,
        predicted-lifetime-value: uint,
        engagement-tier: (string-ascii 15),
        last-updated: uint
    }
)

;; Session counter for unique IDs
(define-data-var session-counter uint u0)
(define-data-var pattern-counter uint u0)

;; Start tracking a new game session
(define-public (start-session-tracking (difficulty uint) (game-mode (string-ascii 20)))
    (let (
        (session-id (var-get session-counter))
        (current-time stacks-block-height)
    )
        (asserts! (var-get metrics-enabled) ERR-NOT-AUTHORIZED)
        (asserts! (<= difficulty u3) ERR-INVALID-INPUT)
        
        (map-set game-sessions
            { session-id: session-id }
            {
                player: tx-sender,
                start-time: current-time,
                end-time: u0,
                duration: u0,
                score: u0,
                completion-rate: u0,
                difficulty-level: difficulty,
                game-mode: game-mode
            }
        )
        
        (var-set session-counter (+ session-id u1))
        (ok session-id)
    )
)

;; End session tracking with final metrics
(define-public (end-session-tracking (session-id uint) (final-score uint) (completion-rate uint))
    (let (
        (session-data (unwrap! (map-get? game-sessions { session-id: session-id }) ERR-DATA-NOT-FOUND))
        (current-time stacks-block-height)
        (duration (- current-time (get start-time session-data)))
    )
        (asserts! (is-eq tx-sender (get player session-data)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get end-time session-data) u0) ERR-INVALID-INPUT)
        (asserts! (<= completion-rate u100) ERR-INVALID-INPUT)
        
        (map-set game-sessions
            { session-id: session-id }
            (merge session-data {
                end-time: current-time,
                duration: duration,
                score: final-score,
                completion-rate: completion-rate
            })
        )
        
        (unwrap-panic (update-player-analytics tx-sender duration (get game-mode session-data) final-score))
        (unwrap-panic (update-behavioral-patterns tx-sender completion-rate duration))
        (ok true)
    )
)

;; Update detailed player analytics
(define-private (update-player-analytics (player principal) (session-duration uint) (game-mode (string-ascii 20)) (score uint))
    (let (
        (current-data (default-to {
            total-playtime: u0,
            average-session-duration: u0,
            preferred-game-mode: "default",
            skill-progression: u0,
            engagement-score: u50,
            last-active: u0,
            sessions-this-week: u0,
            best-streak: u0,
            current-streak: u0
        } (map-get? player-analytics { player: player })))
        (new-total-time (+ (get total-playtime current-data) session-duration))
        (new-sessions (+ (get sessions-this-week current-data) u1))
        (new-avg-duration (/ new-total-time new-sessions))
        (skill-boost (if (> score u80) u10 (if (> score u50) u5 u0)))
        (new-skill (+ (get skill-progression current-data) skill-boost))
        (streak-boost (if (< (- stacks-block-height (get last-active current-data)) u144) 
                         (+ (get current-streak current-data) u1) u1))
        (new-best-streak (if (> streak-boost (get best-streak current-data)) 
                            streak-boost (get best-streak current-data)))
    )
        (map-set player-analytics
            { player: player }
            {
                total-playtime: new-total-time,
                average-session-duration: new-avg-duration,
                preferred-game-mode: game-mode,
                skill-progression: new-skill,
                engagement-score: (if (> (+ (get engagement-score current-data) u5) u100) 
                                     u100 (+ (get engagement-score current-data) u5)),
                last-active: stacks-block-height,
                sessions-this-week: new-sessions,
                best-streak: new-best-streak,
                current-streak: streak-boost
            }
        )
        (ok true)
    )
)

;; Detect and record behavioral patterns
(define-private (update-behavioral-patterns (player principal) (completion-rate uint) (duration uint))
    (let (
        (pattern-id (var-get pattern-counter))
        (pattern-type (if (< completion-rate u25) "early-quitter"
                          (if (> completion-rate u90) "completionist" 
                              (if (< duration u10) "speed-runner"
                                  (if (> duration u100) "explorer" "balanced-player")))))
    )
        (map-set behavioral-patterns
            { pattern-id: pattern-id }
            {
                player: player,
                pattern-type: pattern-type,
                frequency: u1,
                last-occurrence: stacks-block-height,
                confidence-score: u75,
                related-metrics: (list completion-rate duration u0 u0 u0)
            }
        )
        (var-set pattern-counter (+ pattern-id u1))
        (ok true)
    )
)

;; Generate comprehensive analytics report for a player
(define-public (generate-player-report (player principal))
    (let (
        (analytics-data (map-get? player-analytics { player: player }))
        (current-time stacks-block-height)
    )
        (match analytics-data
            player-data
            (begin
                (try! (update-player-segmentation player))
                (ok {
                    total-playtime: (get total-playtime player-data),
                    engagement-level: (get-engagement-level (get engagement-score player-data)),
                    skill-tier: (get-skill-tier (get skill-progression player-data)),
                    activity-status: (get-activity-status (get last-active player-data) current-time),
                    streak-info: {
                        current: (get current-streak player-data),
                        best: (get best-streak player-data)
                    },
                    recommendations: (generate-recommendations player)
                })
            )
            ERR-DATA-NOT-FOUND
        )
    )
)

;; Update player segmentation based on behavior
(define-private (update-player-segmentation (player principal))
    (let (
        (analytics-data (unwrap! (map-get? player-analytics { player: player }) ERR-DATA-NOT-FOUND))
        (engagement (get engagement-score analytics-data))
        (skill (get skill-progression analytics-data))
        (playtime (get total-playtime analytics-data))
        (segment-type (if (and (> engagement u80) (> skill u100)) "power-user"
                          (if (and (> engagement u60) (< skill u50)) "casual-engaged"
                              (if (and (< engagement u40) (> skill u80)) "skilled-inactive"
                                  (if (< playtime u50) "newcomer" "regular-user")))))
        (value-score (+ (/ engagement u2) (/ skill u4) (/ playtime u10)))
    )
        (map-set player-segments
            { player: player }
            {
                segment-type: segment-type,
                value-score: value-score,
                risk-score: (- u100 engagement),
                predicted-lifetime-value: (* value-score u1000),
                engagement-tier: (get-engagement-level engagement),
                last-updated: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Generate personalized recommendations
(define-private (generate-recommendations (player principal))
    (let (
        (analytics-data (unwrap! (map-get? player-analytics { player: player }) (list "no-data")))
        (engagement (get engagement-score analytics-data))
        (skill (get skill-progression analytics-data))
        (avg-duration (get average-session-duration analytics-data))
    )
        (if (< engagement u50) 
            (if (< skill u30) (list "try-new-game-modes" "practice-tutorials")
                (if (> skill u80) (list "try-new-game-modes" "challenge-modes") 
                    (list "try-new-game-modes")))
            (if (< skill u30) (list "practice-tutorials")
                (if (> skill u80) (list "challenge-modes") (list "continue-playing"))))
    )
)

;; Analytics helper functions
(define-private (get-engagement-level (score uint))
    (if (>= score u80) "high"
        (if (>= score u50) "medium" "low")
    )
)

(define-private (get-skill-tier (progression uint))
    (if (>= progression u200) "expert"
        (if (>= progression u100) "intermediate"
            (if (>= progression u50) "novice" "beginner")
        )
    )
)

(define-private (get-activity-status (last-active uint) (current-time uint))
    (let ((time-diff (- current-time last-active)))
        (if (< time-diff u144) "active"
            (if (< time-diff u1440) "recently-active" "inactive")
        )
    )
)

;; Admin functions for analytics management
(define-public (toggle-analytics (enabled bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set metrics-enabled enabled)
        (ok true)
    )
)

(define-public (set-retention-period (blocks uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> blocks u0) ERR-INVALID-INPUT)
        (var-set retention-period blocks)
        (ok true)
    )
)

;; Read-only functions for data access
(define-read-only (get-session-data (session-id uint))
    (ok (map-get? game-sessions { session-id: session-id }))
)

(define-read-only (get-player-analytics (player principal))
    (ok (map-get? player-analytics { player: player }))
)

(define-read-only (get-player-segment (player principal))
    (ok (map-get? player-segments { player: player }))
)

(define-read-only (get-behavioral-pattern (pattern-id uint))
    (ok (map-get? behavioral-patterns { pattern-id: pattern-id }))
)

(define-read-only (get-analytics-status)
    (ok {
        enabled: (var-get metrics-enabled),
        total-sessions: (var-get session-counter),
        total-patterns: (var-get pattern-counter),
        retention-period: (var-get retention-period)
    })
)

