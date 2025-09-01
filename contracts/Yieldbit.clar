(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERR_HARVEST_NOT_VERIFIED (err u105))
(define-constant ERR_SEASON_NOT_ACTIVE (err u106))
(define-constant ERR_INVALID_SEASON (err u107))
(define-constant ERR_POLICY_NOT_FOUND (err u108))
(define-constant ERR_POLICY_EXPIRED (err u109))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u110))
(define-constant ERR_INSUFFICIENT_PREMIUM (err u111))
(define-constant ERR_INVALID_CLAIM_AMOUNT (err u112))
(define-constant ERR_POLICY_ALREADY_EXISTS (err u113))
(define-constant ERR_CLAIM_PERIOD_EXPIRED (err u114))

(define-constant CONTRACT_OWNER tx-sender)
(define-constant TOKEN_NAME "Yieldbit")
(define-constant TOKEN_SYMBOL "YBT")
(define-constant TOKEN_DECIMALS u6)
(define-constant BLOCKS_PER_SEASON u52560)
(define-constant INSURANCE_POOL_FEE u50)
(define-constant BLOCKS_PER_YEAR u210240)
(define-constant MAX_COVERAGE_PERCENTAGE u80)
(define-constant MIN_PREMIUM_RATE u10)
(define-constant CLAIM_PROCESSING_BLOCKS u1440)

(define-data-var total-supply uint u0)
(define-data-var current-season uint u1)
(define-data-var season-start-block uint u0)
(define-data-var total-verified-yield uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var total-policies-issued uint u0)
(define-data-var total-claims-paid uint u0)

(define-map token-balances principal uint)
(define-map token-allowances {owner: principal, spender: principal} uint)

(define-map farmers 
    principal 
    {
        registered: bool,
        total-harvests: uint,
        reputation-score: uint,
        last-harvest-block: uint
    }
)

(define-map harvests 
    {farmer: principal, season: uint, harvest-id: uint}
    {
        yield-amount: uint,
        crop-type: (string-ascii 50),
        verified: bool,
        verification-block: uint,
        verifier: (optional principal),
        tokens-issued: uint
    }
)

(define-map season-stats
    uint
    {
        total-yield: uint,
        total-farmers: uint,
        tokens-distributed: uint,
        harvest-count: uint,
        season-end-block: uint
    }
)

(define-map harvest-counters principal uint)

(define-map insurance-policies
    {farmer: principal, policy-id: uint}
    {
        coverage-amount: uint,
        premium-paid: uint,
        crop-type: (string-ascii 50),
        start-block: uint,
        end-block: uint,
        active: bool,
        claims-made: uint
    }
)

(define-map insurance-claims
    {farmer: principal, policy-id: uint, claim-id: uint}
    {
        loss-amount: uint,
        claim-amount: uint,
        loss-type: (string-ascii 50),
        submitted-block: uint,
        processed: bool,
        approved: bool,
        payout-amount: uint,
        processor: (optional principal)
    }
)

(define-map policy-counters principal uint)
(define-map claim-counters {farmer: principal, policy-id: uint} uint)

(define-read-only (get-name)
    (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

(define-read-only (get-balance (account principal))
    (ok (default-to u0 (map-get? token-balances account)))
)

(define-read-only (get-allowance (owner principal) (spender principal))
    (ok (default-to u0 (map-get? token-allowances {owner: owner, spender: spender})))
)

(define-read-only (get-current-season)
    (ok (var-get current-season))
)

(define-read-only (get-farmer-info (farmer principal))
    (map-get? farmers farmer)
)

(define-read-only (get-harvest-info (farmer principal) (season uint) (harvest-id uint))
    (map-get? harvests {farmer: farmer, season: season, harvest-id: harvest-id})
)

(define-read-only (get-season-stats (season uint))
    (map-get? season-stats season)
)

(define-read-only (get-insurance-policy (farmer principal) (policy-id uint))
    (map-get? insurance-policies {farmer: farmer, policy-id: policy-id})
)

(define-read-only (get-insurance-claim (farmer principal) (policy-id uint) (claim-id uint))
    (map-get? insurance-claims {farmer: farmer, policy-id: policy-id, claim-id: claim-id})
)

(define-read-only (get-insurance-pool-balance)
    (ok (var-get insurance-pool-balance))
)

(define-read-only (get-total-policies-issued)
    (ok (var-get total-policies-issued))
)

(define-read-only (get-total-claims-paid)
    (ok (var-get total-claims-paid))
)

(define-read-only (is-season-active)
    (let ((current-block stacks-block-height)
          (season-start (var-get season-start-block)))
        (< (- current-block season-start) BLOCKS_PER_SEASON)
    )
)

(define-public (register-farmer)
    (let ((farmer tx-sender))
        (asserts! (is-none (map-get? farmers farmer)) ERR_ALREADY_EXISTS)
        (map-set farmers farmer {
            registered: true,
            total-harvests: u0,
            reputation-score: u100,
            last-harvest-block: u0
        })
        (ok true)
    )
)

(define-public (report-harvest (yield-amount uint) (crop-type (string-ascii 50)))
    (let ((farmer tx-sender)
          (current-season-val (var-get current-season))
          (harvest-counter (default-to u0 (map-get? harvest-counters farmer)))
          (new-harvest-id (+ harvest-counter u1)))
        (asserts! (> yield-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-some (map-get? farmers farmer)) ERR_NOT_FOUND)
        (asserts! (is-season-active) ERR_SEASON_NOT_ACTIVE)
        
        (map-set harvest-counters farmer new-harvest-id)
        (map-set harvests {farmer: farmer, season: current-season-val, harvest-id: new-harvest-id} {
            yield-amount: yield-amount,
            crop-type: crop-type,
            verified: false,
            verification-block: u0,
            verifier: none,
            tokens-issued: u0
        })
        
        (map-set farmers farmer 
            (merge (unwrap-panic (map-get? farmers farmer)) 
                   {total-harvests: (+ (get total-harvests (unwrap-panic (map-get? farmers farmer))) u1),
                    last-harvest-block: stacks-block-height}))
        
        (ok new-harvest-id)
    )
)

(define-public (verify-harvest (farmer principal) (season uint) (harvest-id uint))
    (let ((verifier tx-sender)
          (harvest-key {farmer: farmer, season: season, harvest-id: harvest-id})
          (harvest-data (unwrap! (map-get? harvests harvest-key) ERR_NOT_FOUND)))
        (asserts! (or (is-eq verifier CONTRACT_OWNER) (is-farmer-verified verifier)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get verified harvest-data)) ERR_ALREADY_EXISTS)
        
        (let ((yield-amount (get yield-amount harvest-data))
              (tokens-to-issue (calculate-tokens-for-yield yield-amount)))
            
            (map-set harvests harvest-key 
                (merge harvest-data {
                    verified: true,
                    verification-block: stacks-block-height,
                    verifier: (some verifier),
                    tokens-issued: tokens-to-issue
                }))
            
            (unwrap! (mint-tokens farmer tokens-to-issue) ERR_NOT_FOUND)
            (var-set total-verified-yield (+ (var-get total-verified-yield) yield-amount))
            
            (update-farmer-reputation farmer true)
            (update-season-stats season yield-amount tokens-to-issue)
            (ok tokens-to-issue)
        )
    )
)

(define-public (transfer (amount uint) (recipient principal))
    (let ((sender tx-sender)
          (sender-balance (unwrap! (get-balance sender) ERR_NOT_FOUND)))
        ;; (asserts! (>= (unwrap-panic sender-balance) amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; (map-set token-balances sender (- (unwrap-panic sender-balance) amount))
        (map-set token-balances recipient 
            (+ (default-to u0 (map-get? token-balances recipient)) amount))
        
        (ok true)
    )
)

(define-public (approve (spender principal) (amount uint))
    (let ((owner tx-sender))
        (map-set token-allowances {owner: owner, spender: spender} amount)
        (ok true)
    )
)

(define-public (transfer-from (owner principal) (recipient principal) (amount uint))
    (let ((spender tx-sender)
          (allowance (unwrap! (get-allowance owner spender) ERR_NOT_FOUND))
          (owner-balance (unwrap! (get-balance owner) ERR_NOT_FOUND)))
        ;; (asserts! (>= (unwrap-panic allowance) amount) ERR_NOT_AUTHORIZED)
        ;; (asserts! (>= (unwrap-panic owner-balance) amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; (map-set token-allowances {owner: owner, spender: spender} (- (unwrap-panic allowance) amount))
        ;; (map-set token-balances owner (- (unwrap-panic owner-balance) amount))
        (map-set token-balances recipient 
            (+ (default-to u0 (map-get? token-balances recipient)) amount))
        
        (ok true)
    )
)

(define-public (advance-season)
    (let ((current-block stacks-block-height)
          (season-start (var-get season-start-block))
          (current-season-val (var-get current-season)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (>= (- current-block season-start) BLOCKS_PER_SEASON) ERR_SEASON_NOT_ACTIVE)
        
        (finalize-season current-season-val)
        (var-set current-season (+ current-season-val u1))
        (var-set season-start-block current-block)
        (ok (+ current-season-val u1))
    )
)

(define-public (purchase-tokens (stx-amount uint))
    (let ((buyer tx-sender)
          (token-rate u1000)
          (tokens-to-mint (* stx-amount token-rate)))
        (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? stx-amount buyer CONTRACT_OWNER))
        (unwrap! (mint-tokens buyer tokens-to-mint) ERR_NOT_FOUND)
        (ok tokens-to-mint)
    )
)

(define-public (purchase-insurance (coverage-amount uint) (crop-type (string-ascii 50)) (duration-blocks uint))
    (let ((farmer tx-sender)
          (policy-counter (default-to u0 (map-get? policy-counters farmer)))
          (new-policy-id (+ policy-counter u1))
          (premium-amount (calculate-premium coverage-amount duration-blocks))
          (farmer-balance (default-to u0 (map-get? token-balances farmer))))
        (asserts! (> coverage-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= duration-blocks (* BLOCKS_PER_SEASON u1)) ERR_INVALID_AMOUNT)
        (asserts! (<= duration-blocks BLOCKS_PER_YEAR) ERR_INVALID_AMOUNT)
        (asserts! (is-some (map-get? farmers farmer)) ERR_NOT_FOUND)
        (asserts! (>= farmer-balance premium-amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (is-none (map-get? insurance-policies {farmer: farmer, policy-id: new-policy-id})) ERR_POLICY_ALREADY_EXISTS)
        
        (unwrap! (burn-tokens farmer premium-amount) ERR_NOT_FOUND)
        (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) premium-amount))
        
        (map-set policy-counters farmer new-policy-id)
        (map-set insurance-policies {farmer: farmer, policy-id: new-policy-id} {
            coverage-amount: coverage-amount,
            premium-paid: premium-amount,
            crop-type: crop-type,
            start-block: stacks-block-height,
            end-block: (+ stacks-block-height duration-blocks),
            active: true,
            claims-made: u0
        })
        
        (var-set total-policies-issued (+ (var-get total-policies-issued) u1))
        (ok new-policy-id)
    )
)

(define-public (submit-insurance-claim (policy-id uint) (loss-amount uint) (loss-type (string-ascii 50)))
    (let ((farmer tx-sender)
          (policy-key {farmer: farmer, policy-id: policy-id})
          (policy-data (unwrap! (map-get? insurance-policies policy-key) ERR_POLICY_NOT_FOUND))
          (claim-counter (default-to u0 (map-get? claim-counters policy-key)))
          (new-claim-id (+ claim-counter u1))
          (max-claim-amount (/ (* (get coverage-amount policy-data) MAX_COVERAGE_PERCENTAGE) u100)))
        (asserts! (get active policy-data) ERR_POLICY_EXPIRED)
        (asserts! (< stacks-block-height (get end-block policy-data)) ERR_POLICY_EXPIRED)
        (asserts! (> loss-amount u0) ERR_INVALID_CLAIM_AMOUNT)
        (asserts! (<= loss-amount max-claim-amount) ERR_INVALID_CLAIM_AMOUNT)
        
        (map-set claim-counters policy-key new-claim-id)
        (map-set insurance-claims {farmer: farmer, policy-id: policy-id, claim-id: new-claim-id} {
            loss-amount: loss-amount,
            claim-amount: (min loss-amount max-claim-amount),
            loss-type: loss-type,
            submitted-block: stacks-block-height,
            processed: false,
            approved: false,
            payout-amount: u0,
            processor: none
        })
        
        (map-set insurance-policies policy-key 
            (merge policy-data {claims-made: (+ (get claims-made policy-data) u1)}))
        
        (ok new-claim-id)
    )
)

(define-public (process-insurance-claim (farmer principal) (policy-id uint) (claim-id uint) (approve-claim bool))
    (let ((processor tx-sender)
          (claim-key {farmer: farmer, policy-id: policy-id, claim-id: claim-id})
          (claim-data (unwrap! (map-get? insurance-claims claim-key) ERR_NOT_FOUND))
          (policy-data (unwrap! (map-get? insurance-policies {farmer: farmer, policy-id: policy-id}) ERR_POLICY_NOT_FOUND)))
        (asserts! (or (is-eq processor CONTRACT_OWNER) (is-farmer-verified processor)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get processed claim-data)) ERR_CLAIM_ALREADY_PROCESSED)
        (asserts! (< (- stacks-block-height (get submitted-block claim-data)) CLAIM_PROCESSING_BLOCKS) ERR_CLAIM_PERIOD_EXPIRED)
        
        (if approve-claim
            (let ((payout-amount (get claim-amount claim-data)))
                (asserts! (>= (var-get insurance-pool-balance) payout-amount) ERR_INSUFFICIENT_BALANCE)
                (unwrap! (mint-tokens farmer payout-amount) ERR_NOT_FOUND)
                (var-set insurance-pool-balance (- (var-get insurance-pool-balance) payout-amount))
                (var-set total-claims-paid (+ (var-get total-claims-paid) payout-amount))
                
                (map-set insurance-claims claim-key 
                    (merge claim-data {
                        processed: true,
                        approved: true,
                        payout-amount: payout-amount,
                        processor: (some processor)
                    }))
                (ok payout-amount)
            )
            (begin
                (map-set insurance-claims claim-key 
                    (merge claim-data {
                        processed: true,
                        approved: false,
                        payout-amount: u0,
                        processor: (some processor)
                    }))
                (ok u0)
            )
        )
    )
)

(define-public (cancel-insurance-policy (policy-id uint))
    (let ((farmer tx-sender)
          (policy-key {farmer: farmer, policy-id: policy-id})
          (policy-data (unwrap! (map-get? insurance-policies policy-key) ERR_POLICY_NOT_FOUND)))
        (asserts! (get active policy-data) ERR_POLICY_EXPIRED)
        (asserts! (< stacks-block-height (get end-block policy-data)) ERR_POLICY_EXPIRED)
        (asserts! (is-eq (get claims-made policy-data) u0) ERR_CLAIM_ALREADY_PROCESSED)
        
        (let ((refund-amount (/ (get premium-paid policy-data) u2)))
            (map-set insurance-policies policy-key 
                (merge policy-data {active: false}))
            (unwrap! (mint-tokens farmer refund-amount) ERR_NOT_FOUND)
            (var-set insurance-pool-balance (- (var-get insurance-pool-balance) refund-amount))
            (ok refund-amount)
        )
    )
)

(define-private (mint-tokens (recipient principal) (amount uint))
    (let ((current-balance (default-to u0 (map-get? token-balances recipient))))
        (map-set token-balances recipient (+ current-balance amount))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok true)
    )
)

(define-private (burn-tokens (account principal) (amount uint))
    (let ((current-balance (default-to u0 (map-get? token-balances account))))
        (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
        (map-set token-balances account (- current-balance amount))
        (var-set total-supply (- (var-get total-supply) amount))
        (ok true)
    )
)

(define-private (calculate-tokens-for-yield (yield-amount uint))
    (* yield-amount u100)
)

(define-private (calculate-premium (coverage-amount uint) (duration-blocks uint))
    (let ((base-rate MIN_PREMIUM_RATE)
          (duration-factor (/ duration-blocks BLOCKS_PER_SEASON))
          (coverage-factor (/ coverage-amount u1000000)))
        (+ (* coverage-amount base-rate duration-factor) (* coverage-factor u100))
    )
)

(define-private (is-farmer-verified (farmer principal))
    (match (map-get? farmers farmer)
        farmer-data (and (get registered farmer-data) (>= (get reputation-score farmer-data) u75))
        false
    )
)

(define-private (update-farmer-reputation (farmer principal) (positive bool))
    (let ((farmer-data (unwrap-panic (map-get? farmers farmer)))
          (current-rep (get reputation-score farmer-data))
          (new-rep (if positive
                      (min u100 (+ current-rep u5))
                      (max u0 (- current-rep u10)))))
        (map-set farmers farmer 
            (merge farmer-data {reputation-score: new-rep}))
    )
)

(define-private (update-season-stats (season uint) (yield-amount uint) (tokens-issued uint))
    (let ((current-stats (default-to {total-yield: u0, total-farmers: u0, tokens-distributed: u0, harvest-count: u0, season-end-block: u0}
                                   (map-get? season-stats season))))
        (map-set season-stats season {
            total-yield: (+ (get total-yield current-stats) yield-amount),
            total-farmers: (get total-farmers current-stats),
            tokens-distributed: (+ (get tokens-distributed current-stats) tokens-issued),
            harvest-count: (+ (get harvest-count current-stats) u1),
            season-end-block: (get season-end-block current-stats)
        })
    )
)

(define-private (finalize-season (season uint))
    (let ((current-stats (default-to {total-yield: u0, total-farmers: u0, tokens-distributed: u0, harvest-count: u0, season-end-block: u0}
                                   (map-get? season-stats season))))
        (map-set season-stats season 
            (merge current-stats {season-end-block: stacks-block-height}))
    )
)

(define-private (min (a uint) (b uint))
    (if (<= a b) a b)
)

(define-private (max (a uint) (b uint))
    (if (>= a b) a b)
)

