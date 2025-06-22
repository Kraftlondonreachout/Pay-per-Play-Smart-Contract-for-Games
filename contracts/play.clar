;; Pay-per-Play Smart Contract for Games

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLAY-PRICE u1000000) ;; 1 STX
(define-constant DEVELOPER-SHARE u80) ;; 80%
(define-constant COMMUNITY-SHARE u20) ;; 20%

;; data vars
(define-data-var developer-address principal CONTRACT-OWNER)

;; data maps
(define-map player-sessions principal uint)
(define-map revenue-stats { game: principal } { total-plays: uint, total-revenue: uint })

;; public functions
(define-public (start-game-session)
    (let
        (
            (current-sessions (default-to u0 (map-get? player-sessions tx-sender)))
        )
        (try! (stx-transfer? PLAY-PRICE tx-sender (var-get developer-address)))
        (map-set player-sessions tx-sender (+ current-sessions u1))
        (ok true)
    )
)

;; read only functions
(define-read-only (get-player-sessions (player principal))
    (ok (default-to u0 (map-get? player-sessions player)))
)

(define-read-only (get-play-price)
    (ok PLAY-PRICE)
)

;; admin functions
(define-public (set-developer-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err true))
        (ok (var-set developer-address new-address))
    )
)



;; Add to data vars
(define-data-var refund-window uint u3600) ;; 1 hour in seconds
(define-map last-play-timestamp principal uint)

;; Add new function
(define-public (request-refund)
    (let 
        (
            (last-timestamp (default-to u0 (map-get? last-play-timestamp tx-sender)))
            (current-time stacks-block-height)
        )
        (asserts! (< (- current-time last-timestamp) (var-get refund-window)) (err u100))
        (try! (stx-transfer? PLAY-PRICE (var-get developer-address) tx-sender))
        (ok true)
    )
)



;; Add to data maps
(define-map tier-prices 
    { tier: uint } 
    { price: uint, playtime: uint }
)

;; Add function
(define-public (start-tiered-session (tier-id uint))
    (let 
        ((tier-info (unwrap! (map-get? tier-prices {tier: tier-id}) (err u101))))
        (try! (stx-transfer? (get price tier-info) tx-sender (var-get developer-address)))
        (ok true)
    )
)




;; Add to data maps
(define-map player-achievements 
    { player: principal } 
    { achievements: (list 10 uint) }
)

;; Add function
(define-public (unlock-achievement (achievement-id uint))
    (let
        ((current-achievements (default-to {achievements: (list)} (map-get? player-achievements {player: tx-sender}))))
        (map-set player-achievements 
            {player: tx-sender}
            {achievements: (unwrap! (as-max-len? (append (get achievements current-achievements) achievement-id) u10) (err u102))})
        (ok true)
    )
)




;; Add to data vars
(define-data-var subscription-price uint u10000000) ;; 10 STX
(define-map subscriptions 
    { subscriber: principal } 
    { expiry: uint }
)

;; Add function
(define-public (purchase-subscription)
    (begin
        (try! (stx-transfer? (var-get subscription-price) tx-sender (var-get developer-address)))
        (map-set subscriptions 
            {subscriber: tx-sender}
            {expiry: (+ stacks-block-height u1440)}) ;; 1 day subscription
        (ok true)
    )
)



;; Add to data maps
(define-map referral-rewards 
    { referrer: principal } 
    { total-rewards: uint }
)

;; Add function
(define-public (play-with-referral (referrer principal))
    (begin
        (try! (stx-transfer? PLAY-PRICE tx-sender (var-get developer-address)))
        (try! (stx-transfer? (/ PLAY-PRICE u10) (var-get developer-address) referrer))
        (ok true)
    )
)




;; Add to data maps
(define-map player-stats
    { player: principal }
    { total-time: uint, high-score: uint }
)

;; Add function
(define-public (update-player-stats (play-time uint) (score uint))
    (let
        ((current-stats (default-to {total-time: u0, high-score: u0} (map-get? player-stats {player: tx-sender}))))
        (map-set player-stats
            {player: tx-sender}
            {
                total-time: (+ (get total-time current-stats) play-time),
                high-score: (if (> score (get high-score current-stats)) score (get high-score current-stats))
            }
        )
        (ok true)
    )
)



;; Add to data maps
(define-map game-ratings
    { player: principal }
    { rating: uint }
)

;; Add function
(define-public (rate-game (rating uint))
    (begin
        (asserts! (<= rating u5) (err u103))
        (map-set game-ratings
            {player: tx-sender}
            {rating: rating}
        )
        (ok true)
    )
)


;; Add to data maps
(define-map tournaments 
    { tournament-id: uint } 
    { entry-fee: uint, prize-pool: uint, participants: (list 50 principal), active: bool }
)

(define-data-var tournament-counter uint u0)

;; Add functions
(define-public (create-tournament (entry-fee uint))
    (let
        ((tournament-id (var-get tournament-counter)))
        (map-set tournaments
            {tournament-id: tournament-id}
            {
                entry-fee: entry-fee,
                prize-pool: u0,
                participants: (list),
                active: true
            }
        )
        (var-set tournament-counter (+ tournament-id u1))
        (ok tournament-id)
    )
)

(define-public (join-tournament (tournament-id uint))
    (let
        ((tournament (unwrap! (map-get? tournaments {tournament-id: tournament-id}) (err u200))))
        (try! (stx-transfer? (get entry-fee tournament) tx-sender (var-get developer-address)))
        (map-set tournaments
            {tournament-id: tournament-id}
            (merge tournament 
                {
                    prize-pool: (+ (get prize-pool tournament) (get entry-fee tournament)),
                    participants: (unwrap! (as-max-len? (append (get participants tournament) tx-sender) u50) (err u201))
                }
            )
        )
        (ok true)
    )
)


;; Add to data maps
(define-map leaderboard
    { season: uint }
    { top-players: (list 100 {player: principal, score: uint}) }
)

(define-data-var current-season uint u1)

(define-public (submit-score (score uint))
    (let
        ((season (var-get current-season)))
        (map-set leaderboard
            {season: season}
            {top-players: (unwrap! (as-max-len? 
                (append (default-to (list) (get top-players (map-get? leaderboard {season: season}))) 
                {player: tx-sender, score: score}) 
                u100) (err u301))}
        )
        (ok true)
    )
)


;; Add to data maps
(define-map game-items
    { item-id: uint }
    { price: uint, name: (string-ascii 50), available: bool }
)

(define-map player-inventory
    { player: principal }
    { owned-items: (list 100 uint) }
)

(define-public (purchase-item (item-id uint))
    (let
        ((item (unwrap! (map-get? game-items {item-id: item-id}) (err u400))))
        (asserts! (get available item) (err u401))
        (try! (stx-transfer? (get price item) tx-sender (var-get developer-address)))
        (map-set player-inventory
            {player: tx-sender}
            {owned-items: (unwrap! (as-max-len? 
                (append (default-to (list) (get owned-items (map-get? player-inventory {player: tx-sender}))) 
                item-id) 
                u100) (err u402))}
        )
        (ok true)
    )
)


;; Add to data maps
(define-map guilds
    { guild-id: uint }
    { name: (string-ascii 50), leader: principal, members: (list 50 principal) }
)

(define-data-var guild-counter uint u0)

(define-public (create-guild (guild-name (string-ascii 50)))
    (let
        ((guild-id (var-get guild-counter)))
        (map-set guilds
            {guild-id: guild-id}
            {
                name: guild-name,
                leader: tx-sender,
                members: (list tx-sender)
            }
        )
        (var-set guild-counter (+ guild-id u1))
        (ok guild-id)
    )
)

(define-public (join-guild (guild-id uint))
    (let
        ((guild (unwrap! (map-get? guilds {guild-id: guild-id}) (err u600))))
        (map-set guilds
            {guild-id: guild-id}
            (merge guild 
                {members: (unwrap! (as-max-len? (append (get members guild) tx-sender) u50) (err u601))}
            )
        )
        (ok true)
    )
)




;; Add to data maps
(define-map trade-offers
    { trade-id: uint }
    { 
        from: principal,
        to: principal,
        item-offered: uint,
        item-requested: uint,
        status: (string-ascii 20)
    }
)

(define-data-var trade-counter uint u0)

(define-public (create-trade-offer (to principal) (item-offered uint) (item-requested uint))
    (let
        ((trade-id (var-get trade-counter)))
        (map-set trade-offers
            {trade-id: trade-id}
            {
                from: tx-sender,
                to: to,
                item-offered: item-offered,
                item-requested: item-requested,
                status: "pending"
            }
        )
        (var-set trade-counter (+ trade-id u1))
        (ok trade-id)
    )
)



;; Add to data maps
(define-map game-events
    { event-id: uint }
    {
        name: (string-ascii 50),
        reward: uint,
        start-block: uint,
        end-block: uint,
        participants: (list 100 principal)
    }
)

(define-data-var event-counter uint u0)

(define-public (create-game-event (name (string-ascii 50)) (reward uint) (duration uint))
    (let
        ((event-id (var-get event-counter)))
        (map-set game-events
            {event-id: event-id}
            {
                name: name,
                reward: reward,
                start-block: stacks-block-height,
                end-block: (+ stacks-block-height duration),
                participants: (list)
            }
        )
        (var-set event-counter (+ event-id u1))
        (ok event-id)
    )
)



;; Add to data vars
(define-data-var rewards-threshold uint u10) ;; Number of plays needed for reward
(define-data-var reward-bonus uint u2000000) ;; 2 STX reward

;; Add to data maps
(define-map player-rewards 
    { player: principal } 
    { plays-count: uint, rewards-claimed: uint }
)

(define-public (claim-loyalty-reward)
    (let 
        ((player-data (default-to {plays-count: u0, rewards-claimed: u0} 
            (map-get? player-rewards {player: tx-sender})))
         (current-plays (default-to u0 (map-get? player-sessions tx-sender))))
        
        (asserts! (>= current-plays (+ (* (get rewards-claimed player-data) (var-get rewards-threshold)) 
            (var-get rewards-threshold))) (err u1))
            
        (try! (stx-transfer? (var-get reward-bonus) (var-get developer-address) tx-sender))
        
        (map-set player-rewards 
            {player: tx-sender}
            {plays-count: current-plays, 
             rewards-claimed: (+ (get rewards-claimed player-data) u1)})
        (ok true)
    )
)



;; Add to data vars
(define-data-var pass-price uint u50000000) ;; 50 STX
(define-data-var pass-duration uint u144) ;; 24 hours in blocks

;; Add to data maps
(define-map game-passes
    { holder: principal }
    { expiry: uint }
)

(define-public (purchase-game-pass)
    (begin
        (try! (stx-transfer? (var-get pass-price) tx-sender (var-get developer-address)))
        (map-set game-passes
            {holder: tx-sender}
            {expiry: (+ stacks-block-height (var-get pass-duration))})
        (ok true)
    )
)

(define-map player-levels
    { player: principal }
    { 
        level: uint,
        experience: uint
    }
)

(define-data-var exp-per-game uint u100)
(define-data-var exp-per-level uint u1000)
(define-data-var max-level uint u50)

(define-public (add-experience (game-score uint))
    (let (
        (current-data (default-to { level: u1, experience: u0 } 
            (map-get? player-levels { player: tx-sender })))
        (new-exp (+ (get experience current-data) (var-get exp-per-game)))
        (current-level (get level current-data))
    )
        (asserts! (<= current-level (var-get max-level)) (err u2000))
        
        (if (>= new-exp (var-get exp-per-level))
            (map-set player-levels 
                { player: tx-sender }
                { 
                    level: (+ current-level u1),
                    experience: (- new-exp (var-get exp-per-level))
                }
            )
            (map-set player-levels 
                { player: tx-sender }
                { 
                    level: current-level,
                    experience: new-exp
                }
            )
        )
        (ok true)
    )
)

(define-map daily-challenges
    { challenge-id: uint }
    { 
        name: (string-ascii 50),
        target-score: uint,
        reward: uint,
        active: bool
    }
)

(define-data-var challenge-counter uint u0)

(define-map challenge-completions
    { player: principal, day: uint }
    { completed: bool }
)

(define-data-var challenge-reward uint u5000000)
(define-public (create-daily-challenge (name (string-ascii 50)) (target-score uint) (reward uint))
    (let (
        (challenge-id (var-get challenge-counter))
        (today-block (/ stacks-block-height u144))
    )
        (map-set daily-challenges 
            { challenge-id: challenge-id }
            { 
                name: name,
                target-score: target-score,
                reward: reward,
                active: true
            }
        )
        (var-set challenge-counter (+ challenge-id u1))
        (ok true)
    )
)
(define-public (activate-daily-challenge (challenge-id uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
    )
        (asserts! (not (get active challenge)) (err u1001))
        (map-set daily-challenges 
            { challenge-id: challenge-id }
            { 
                name: (get name challenge),
                target-score: (get target-score challenge),
                reward: (get reward challenge),
                active: true
            }
        )
        (ok true)
    )
)
(define-public (deactivate-daily-challenge (challenge-id uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
    )
        (asserts! (get active challenge) (err u1001))
        (map-set daily-challenges 
            { challenge-id: challenge-id }
            { 
                name: (get name challenge),
                target-score: (get target-score challenge),
                reward: (get reward challenge),
                active: false
            }
        )
        (ok true)
    )
)
(define-public (get-daily-challenge (challenge-id uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
    )
        (ok challenge)
    )
)
(define-public (get-challenge-completion (challenge-id uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
        (today-block (/ stacks-block-height u144))
    )
        (ok (default-to false (get completed (map-get? challenge-completions { player: tx-sender, day: today-block }))))
    )
)
(define-public (get-challenge-completion-status (challenge-id uint) (player principal))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
        (today-block (/ stacks-block-height u144))
    )
        (ok (default-to false (get completed (map-get? challenge-completions { player: player, day: today-block }))))
    )
)
(define-public (get-challenge-completion-status-by-day (challenge-id uint) (day uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
    )
        (ok (default-to false (get completed (map-get? challenge-completions { player: tx-sender, day: day }))))
    )
)
(define-public (get-challenge-completion-status-by-day-and-player (challenge-id uint) (day uint) (player principal))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1000)))
    )
        (ok (default-to false (get completed (map-get? challenge-completions { player: player, day: day }))))
    )
)
    


(define-public (complete-daily-challenge (challenge-id uint) (score uint))
    (let (
        (challenge (unwrap! (map-get? daily-challenges { challenge-id: challenge-id }) (err u1001)))
        (today-block (/ stacks-block-height u144))
    )
        (asserts! (get active challenge) (err u1002))
        (asserts! (>= score (get target-score challenge)) (err u1003))
        (asserts! (not (default-to false (get completed (map-get? challenge-completions { player: tx-sender, day: today-block })))) (err u1004))
        
        (try! (stx-transfer? (get reward challenge) (var-get developer-address) tx-sender))
        (map-set challenge-completions { player: tx-sender, day: today-block } { completed: true })
        (ok true)
    )
)

(define-data-var base-price uint u1000000)
(define-data-var price-multiplier uint u100)
(define-data-var demand-threshold uint u10)
(define-data-var time-based-discount uint u20)

(define-map hourly-play-count
    { hour: uint }
    { plays: uint }
)

(define-map price-history
    { block-height: uint }
    { price: uint }
)

(define-private (get-current-hour)
    (mod (/ stacks-block-height u6) u24)
)

(define-private (get-hourly-plays)
    (default-to u0 (get plays (map-get? hourly-play-count { hour: (get-current-hour) })))
)

(define-private (calculate-demand-multiplier)
    (let ((current-plays (get-hourly-plays)))
        (if (> current-plays (var-get demand-threshold))
            (+ u100 (* (- current-plays (var-get demand-threshold)) u10))
            u100
        )
    )
)

(define-private (calculate-time-discount)
    (let ((hour (get-current-hour)))
        (if (or (< hour u8) (> hour u22))
            (- u100 (var-get time-based-discount))
            u100
        )
    )
)

(define-private (get-dynamic-price)
    (let (
        (base (var-get base-price))
        (demand-mult (calculate-demand-multiplier))
        (time-mult (calculate-time-discount))
    )
        (/ (* (* base demand-mult) time-mult) u10000)
    )
)

(define-private (update-hourly-count)
    (let (
        (current-hour (get-current-hour))
        (current-plays (get-hourly-plays))
    )
        (map-set hourly-play-count
            { hour: current-hour }
            { plays: (+ current-plays u1) }
        )
    )
)

(define-public (start-dynamic-game-session)
    (let (
        (current-price (get-dynamic-price))
    )
        (try! (stx-transfer? current-price tx-sender (var-get developer-address)))
        (update-hourly-count)
        (map-set price-history
            { block-height: stacks-block-height }
            { price: current-price }
        )
        (map-set player-sessions tx-sender 
            (+ (default-to u0 (map-get? player-sessions tx-sender)) u1))
        (ok current-price)
    )
)

(define-read-only (get-current-price)
    (ok (get-dynamic-price))
)

(define-read-only (get-price-factors)
    (ok {
        base-price: (var-get base-price),
        demand-multiplier: (calculate-demand-multiplier),
        time-multiplier: (calculate-time-discount),
        current-hour: (get-current-hour),
        hourly-plays: (get-hourly-plays)
    })
)

(define-public (set-pricing-parameters (new-base-price uint) (new-multiplier uint) (new-threshold uint) (new-discount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err u5000))
        (var-set base-price new-base-price)
        (var-set price-multiplier new-multiplier)
        (var-set demand-threshold new-threshold)
        (var-set time-based-discount new-discount)
        (ok true)
    )
)

(define-read-only (get-price-history (block-heigh uint))
    (ok (map-get? price-history { block-height: stacks-block-height }))
)