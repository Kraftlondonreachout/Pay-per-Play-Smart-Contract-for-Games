;; Session Recovery System
;; Handles interrupted game sessions and provides recovery mechanisms for players

;; Error constants
(define-constant err-unauthorized (err u500))
(define-constant err-not-found (err u501))
(define-constant err-session-expired (err u502))
(define-constant err-session-completed (err u503))
(define-constant err-invalid-refund (err u504))
(define-constant err-recovery-used (err u505))

;; Configuration constants  
(define-constant CONTRACT-OWNER tx-sender)
(define-constant RECOVERY-WINDOW u144)      ;; 24 hours in blocks
(define-constant MIN-SESSION-TIME u5)       ;; Minimum blocks for valid session
(define-constant REFUND-PERCENTAGE u75)     ;; 75% refund for interrupted sessions

;; Data variables
(define-data-var recovery-enabled bool true)
(define-data-var total-recoveries uint u0)
(define-data-var total-refunds-issued uint u0)

;; Active session tracking
(define-map active-sessions
  { player: principal }
  {
    session-start: uint,
    payment-amount: uint,
    game-mode: (string-ascii 20),
    recovery-used: bool,
    heartbeat-block: uint
  }
)

;; Recovery attempts tracking
(define-map recovery-attempts
  { player: principal, attempt-id: uint }
  {
    original-session-start: uint,
    recovery-block: uint,
    success: bool,
    refund-amount: uint
  }
)

;; Session reliability metrics
(define-map reliability-stats
  { time-period: uint }
  {
    total-sessions: uint,
    completed-sessions: uint,
    interrupted-sessions: uint,
    recovery-success-rate: uint
  }
)

;; Player recovery history
(define-map player-recovery-stats
  { player: principal }
  {
    total-recoveries: uint,
    successful-recoveries: uint,
    total-refunds-received: uint,
    reliability-score: uint
  }
)

;; Data variables for tracking
(define-data-var last-attempt-id uint u0)

;; Start tracking an active session
(define-public (start-session-tracking (payment-amount uint) (game-mode (string-ascii 20)))
  (let
    (
      (existing-session (map-get? active-sessions { player: tx-sender }))
    )
    (asserts! (var-get recovery-enabled) err-unauthorized)
    (asserts! (> payment-amount u0) err-invalid-refund)
    
    ;; Clean up any existing session first
    (match existing-session
      session (try! (cleanup-abandoned-session))
      true
    )
    
    (map-set active-sessions
      { player: tx-sender }
      {
        session-start: stacks-block-height,
        payment-amount: payment-amount,
        game-mode: game-mode,
        recovery-used: false,
        heartbeat-block: stacks-block-height
      }
    )
    (ok true)
  )
)

;; Update session heartbeat (called during gameplay)
(define-public (update-session-heartbeat)
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: tx-sender }) err-not-found))
    )
    (map-set active-sessions
      { player: tx-sender }
      (merge session { heartbeat-block: stacks-block-height })
    )
    (ok true)
  )
)

;; Complete session successfully
(define-public (complete-session)
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: tx-sender }) err-not-found))
      (session-duration (- stacks-block-height (get session-start session)))
    )
    (asserts! (>= session-duration MIN-SESSION-TIME) err-invalid-refund)
    
    ;; Update reliability stats
    (update-reliability-stats true)
    
    ;; Remove active session
    (map-delete active-sessions { player: tx-sender })
    (ok true)
  )
)

;; Attempt to recover an interrupted session
(define-public (recover-interrupted-session)
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: tx-sender }) err-not-found))
      (time-since-start (- stacks-block-height (get session-start session)))
      (time-since-heartbeat (- stacks-block-height (get heartbeat-block session)))
      (new-attempt-id (+ (var-get last-attempt-id) u1))
    )
    (asserts! (< time-since-start RECOVERY-WINDOW) err-session-expired)
    (asserts! (not (get recovery-used session)) err-recovery-used)
    (asserts! (> time-since-heartbeat u10) err-session-completed)
    
    ;; Mark recovery as used
    (map-set active-sessions
      { player: tx-sender }
      (merge session { recovery-used: true })
    )
    
    ;; Record recovery attempt
    (var-set last-attempt-id new-attempt-id)
    (map-set recovery-attempts
      { player: tx-sender, attempt-id: new-attempt-id }
      {
        original-session-start: (get session-start session),
        recovery-block: stacks-block-height,
        success: true,
        refund-amount: u0
      }
    )
    
    ;; Update player recovery stats
    (update-player-recovery-stats true false)
    (var-set total-recoveries (+ (var-get total-recoveries) u1))
    
    (ok new-attempt-id)
  )
)

;; Request refund for unplayable session
(define-public (request-session-refund)
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: tx-sender }) err-not-found))
      (time-since-start (- stacks-block-height (get session-start session)))
      (time-since-heartbeat (- stacks-block-height (get heartbeat-block session)))
      (payment-amount (get payment-amount session))
      (refund-amount (/ (* payment-amount REFUND-PERCENTAGE) u100))
      (new-attempt-id (+ (var-get last-attempt-id) u1))
    )
    (asserts! (< time-since-start RECOVERY-WINDOW) err-session-expired)
    (asserts! (> time-since-heartbeat u20) err-session-completed)
    (asserts! (< time-since-start u30) err-invalid-refund)
    
    ;; Process refund
    (try! (as-contract (stx-transfer? refund-amount (as-contract tx-sender) tx-sender)))
    
    ;; Record refund attempt
    (var-set last-attempt-id new-attempt-id)
    (map-set recovery-attempts
      { player: tx-sender, attempt-id: new-attempt-id }
      {
        original-session-start: (get session-start session),
        recovery-block: stacks-block-height,
        success: false,
        refund-amount: refund-amount
      }
    )
    
    ;; Update stats
    (update-player-recovery-stats false true)
    (update-reliability-stats false)
    (var-set total-refunds-issued (+ (var-get total-refunds-issued) refund-amount))
    
    ;; Remove session
    (map-delete active-sessions { player: tx-sender })
    (ok refund-amount)
  )
)

;; Clean up abandoned session (internal function)
(define-private (cleanup-abandoned-session)
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: tx-sender }) err-not-found))
      (time-since-start (- stacks-block-height (get session-start session)))
    )
    (if (> time-since-start RECOVERY-WINDOW)
      (begin
        (map-delete active-sessions { player: tx-sender })
        (update-reliability-stats false)
        (ok true)
      )
      (ok true)
    )
  )
)

;; Update platform reliability statistics
(define-private (update-reliability-stats (completed bool))
  (let
    (
      (period-key (- stacks-block-height (mod stacks-block-height RECOVERY-WINDOW)))
      (existing-stats (default-to
        { total-sessions: u0, completed-sessions: u0, interrupted-sessions: u0, recovery-success-rate: u0 }
        (map-get? reliability-stats { time-period: period-key })
      ))
      (new-total (+ (get total-sessions existing-stats) u1))
      (new-completed (if completed (+ (get completed-sessions existing-stats) u1) (get completed-sessions existing-stats)))
      (new-interrupted (if completed (get interrupted-sessions existing-stats) (+ (get interrupted-sessions existing-stats) u1)))
    )
    (map-set reliability-stats
      { time-period: period-key }
      {
        total-sessions: new-total,
        completed-sessions: new-completed,
        interrupted-sessions: new-interrupted,
        recovery-success-rate: (if (> new-total u0) (/ (* new-completed u100) new-total) u0)
      }
    )
    true
  )
)

;; Update individual player recovery statistics
(define-private (update-player-recovery-stats (recovery-success bool) (refund-received bool))
  (let
    (
      (existing-stats (default-to
        { total-recoveries: u0, successful-recoveries: u0, total-refunds-received: u0, reliability-score: u100 }
        (map-get? player-recovery-stats { player: tx-sender })
      ))
      (new-total (+ (get total-recoveries existing-stats) u1))
      (new-successful (if recovery-success (+ (get successful-recoveries existing-stats) u1) (get successful-recoveries existing-stats)))
    )
    (map-set player-recovery-stats
      { player: tx-sender }
      {
        total-recoveries: new-total,
        successful-recoveries: new-successful,
        total-refunds-received: (get total-refunds-received existing-stats),
        reliability-score: (if (> new-total u0) (/ (* new-successful u100) new-total) u100)
      }
    )
    true
  )
)

;; Read-only functions
(define-read-only (get-active-session (player principal))
  (map-get? active-sessions { player: player })
)

(define-read-only (get-recovery-attempt (player principal) (attempt-id uint))
  (map-get? recovery-attempts { player: player, attempt-id: attempt-id })
)

(define-read-only (get-player-recovery-stats (player principal))
  (map-get? player-recovery-stats { player: player })
)

(define-read-only (get-platform-reliability (period uint))
  (map-get? reliability-stats { time-period: period })
)

(define-read-only (get-recovery-system-stats)
  (ok {
    enabled: (var-get recovery-enabled),
    total-recoveries: (var-get total-recoveries),
    total-refunds-issued: (var-get total-refunds-issued),
    recovery-window-blocks: RECOVERY-WINDOW,
    refund-percentage: REFUND-PERCENTAGE
  })
)

;; Admin functions
(define-public (toggle-recovery-system (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) err-unauthorized)
    (var-set recovery-enabled enabled)
    (ok true)
  )
)

(define-public (force-cleanup-session (player principal))
  (let
    (
      (session (unwrap! (map-get? active-sessions { player: player }) err-not-found))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) err-unauthorized)
    (map-delete active-sessions { player: player })
    (ok true)
  )
)
