(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-REPUTATION u10000)
(define-constant MIN-REPUTATION u0)
(define-constant STARTING-REPUTATION u5000)
(define-constant VOTE-WEIGHT-THRESHOLD u2000)

(define-data-var reputation-decay-rate uint u10)
(define-data-var vote-cost uint u100000)

(define-map player-reputation
    { player: principal }
    { 
        score: uint,
        last-updated: uint,
        positive-votes: uint,
        negative-votes: uint,
        total-games: uint
    }
)

(define-map reputation-actions
    { action-id: uint }
    {
        player: principal,
        action-type: (string-ascii 20),
        reputation-change: int,
        timestamp: uint,
        reporter: principal
    }
)

(define-map community-votes
    { voter: principal, target: principal, vote-id: uint }
    { vote-type: bool, timestamp: uint }
)

(define-map reputation-rewards
    { threshold: uint }
    { reward-amount: uint, unlock-features: (list 5 (string-ascii 30)) }
)

(define-data-var action-counter uint u0)
(define-data-var vote-counter uint u0)

(define-private (get-reputation-data (player principal))
    (default-to 
        { score: STARTING-REPUTATION, last-updated: u0, positive-votes: u0, negative-votes: u0, total-games: u0 }
        (map-get? player-reputation { player: player })
    )
)

(define-private (apply-time-decay (current-score uint) (last-updated uint))
    (let ((blocks-passed (- stacks-block-height last-updated)))
        (if (> blocks-passed u1440)
            (let ((decay-amount (/ (* blocks-passed (var-get reputation-decay-rate)) u1440)))
                (if (> current-score decay-amount)
                    (- current-score decay-amount)
                    MIN-REPUTATION
                )
            )
            current-score
        )
    )
)

(define-private (calculate-new-reputation (current-score uint) (change int))
    (if (> change 0)
        (let ((new-score (+ current-score (to-uint change))))
            (if (> new-score MAX-REPUTATION) MAX-REPUTATION new-score)
        )
        (let ((decrease (to-uint (- 0 change))))
            (if (> current-score decrease)
                (- current-score decrease)
                MIN-REPUTATION
            )
        )
    )
)

(define-public (initialize-player-reputation)
    (let ((existing-data (map-get? player-reputation { player: tx-sender })))
        (asserts! (is-none existing-data) (err u1001))
        (map-set player-reputation
            { player: tx-sender }
            { 
                score: STARTING-REPUTATION,
                last-updated: stacks-block-height,
                positive-votes: u0,
                negative-votes: u0,
                total-games: u0
            }
        )
        (ok true)
    )
)

(define-public (update-reputation-for-game (player principal) (performance-score uint) (fair-play bool))
    (let (
        (current-data (get-reputation-data player))
        (decayed-score (apply-time-decay (get score current-data) (get last-updated current-data)))
        (performance-bonus (if (> performance-score u80) 50 (if (> performance-score u50) 25 0)))
        (fair-play-bonus (if fair-play 25 -50))
        (total-change (+ performance-bonus fair-play-bonus))
        (new-score (calculate-new-reputation decayed-score total-change))
    )
        (map-set player-reputation
            { player: player }
            {
                score: new-score,
                last-updated: stacks-block-height,
                positive-votes: (get positive-votes current-data),
                negative-votes: (get negative-votes current-data),
                total-games: (+ (get total-games current-data) u1)
            }
        )
        (map-set reputation-actions
            { action-id: (var-get action-counter) }
            {
                player: player,
                action-type: "game-performance",
                reputation-change: total-change,
                timestamp: stacks-block-height,
                reporter: tx-sender
            }
        )
        (var-set action-counter (+ (var-get action-counter) u1))
        (ok new-score)
    )
)

(define-public (vote-on-player-reputation (target-player principal) (positive-vote bool))
    (let (
        (voter-data (get-reputation-data tx-sender))
        (target-data (get-reputation-data target-player))
        (vote-id (var-get vote-counter))
    )
        (asserts! (not (is-eq tx-sender target-player)) (err u1002))
        (asserts! (>= (get score voter-data) VOTE-WEIGHT-THRESHOLD) (err u1003))
        (asserts! (is-none (map-get? community-votes { voter: tx-sender, target: target-player, vote-id: vote-id })) (err u1004))
        
        (try! (stx-transfer? (var-get vote-cost) tx-sender tx-sender))
        
        (map-set community-votes
            { voter: tx-sender, target: target-player, vote-id: vote-id }
            { vote-type: positive-vote, timestamp: stacks-block-height }
        )
        
        (let (
            (reputation-change (if positive-vote 100 -100))
            (decayed-score (apply-time-decay (get score target-data) (get last-updated target-data)))
            (new-score (calculate-new-reputation decayed-score reputation-change))
            (new-positive (if positive-vote (+ (get positive-votes target-data) u1) (get positive-votes target-data)))
            (new-negative (if positive-vote (get negative-votes target-data) (+ (get negative-votes target-data) u1)))
        )
            (map-set player-reputation
                { player: target-player }
                {
                    score: new-score,
                    last-updated: stacks-block-height,
                    positive-votes: new-positive,
                    negative-votes: new-negative,
                    total-games: (get total-games target-data)
                }
            )
        )
        
        (var-set vote-counter (+ vote-id u1))
        (ok true)
    )
)

(define-public (claim-reputation-reward (threshold uint))
    (let (
        (player-data (get-reputation-data tx-sender))
        (reward-info (unwrap! (map-get? reputation-rewards { threshold: threshold }) (err u1005)))
        (decayed-score (apply-time-decay (get score player-data) (get last-updated player-data)))
    )
        (asserts! (>= decayed-score threshold) (err u1006))
        (try! (stx-transfer? (get reward-amount reward-info) tx-sender tx-sender))
        (ok (get unlock-features reward-info))
    )
)

(define-public (report-misconduct (target-player principal) (severity uint))
    (let (
        (reporter-data (get-reputation-data tx-sender))
        (target-data (get-reputation-data target-player))
        (penalty (if (is-eq severity u3) -200 (if (is-eq severity u2) -100 -50)))
        (decayed-score (apply-time-decay (get score target-data) (get last-updated target-data)))
        (new-score (calculate-new-reputation decayed-score penalty))
    )
        (asserts! (not (is-eq tx-sender target-player)) (err u1007))
        (asserts! (>= (get score reporter-data) VOTE-WEIGHT-THRESHOLD) (err u1008))
        (asserts! (<= severity u3) (err u1009))
        
        (map-set player-reputation
            { player: target-player }
            {
                score: new-score,
                last-updated: stacks-block-height,
                positive-votes: (get positive-votes target-data),
                negative-votes: (+ (get negative-votes target-data) u1),
                total-games: (get total-games target-data)
            }
        )
        
        (map-set reputation-actions
            { action-id: (var-get action-counter) }
            {
                player: target-player,
                action-type: "misconduct-report",
                reputation-change: penalty,
                timestamp: stacks-block-height,
                reporter: tx-sender
            }
        )
        (var-set action-counter (+ (var-get action-counter) u1))
        (ok true)
    )
)

(define-public (set-reputation-rewards (threshold uint) (reward-amount uint) (features (list 5 (string-ascii 30))))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err u1010))
        (map-set reputation-rewards
            { threshold: threshold }
            { reward-amount: reward-amount, unlock-features: features }
        )
        (ok true)
    )
)

(define-read-only (get-player-reputation (player principal))
    (let ((data (get-reputation-data player)))
        (ok {
            score: (apply-time-decay (get score data) (get last-updated data)),
            positive-votes: (get positive-votes data),
            negative-votes: (get negative-votes data),
            total-games: (get total-games data),
            reputation-level: (get-reputation-level (apply-time-decay (get score data) (get last-updated data)))
        })
    )
)

(define-read-only (get-reputation-level (score uint))
    (if (>= score u9000) "legendary"
        (if (>= score u7500) "master"
            (if (>= score u6000) "expert" 
                (if (>= score u4000) "veteran"
                    (if (>= score u2500) "regular"
                        (if (>= score u1000) "newcomer" "untrusted")
                    )
                )
            )
        )
    )
)

(define-read-only (check-reputation-access (player principal) (required-score uint))
    (let ((data (get-reputation-data player)))
        (ok (>= (apply-time-decay (get score data) (get last-updated data)) required-score))
    )
)

(define-read-only (get-reputation-history (player principal) (limit uint))
    (ok "reputation-history-placeholder")
)

(define-read-only (get-top-reputation-players (limit uint))
    (ok "top-players-placeholder")
)
