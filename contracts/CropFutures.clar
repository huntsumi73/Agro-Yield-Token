;; Crop Futures Market - Decentralized agricultural futures trading
;; Enables farmers to sell future harvests at locked prices

;; Error constants
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_CONTRACT_NOT_FOUND (err u201))
(define-constant ERR_CONTRACT_EXPIRED (err u202))
(define-constant ERR_CONTRACT_FULFILLED (err u203))
(define-constant ERR_INSUFFICIENT_DEPOSIT (err u204))
(define-constant ERR_INVALID_AMOUNT (err u205))
(define-constant ERR_INVALID_PRICE (err u206))
(define-constant ERR_INVALID_DELIVERY_DATE (err u207))
(define-constant ERR_NOT_BUYER (err u208))
(define-constant ERR_NOT_SELLER (err u209))
(define-constant ERR_HARVEST_NOT_READY (err u210))
(define-constant ERR_CONTRACT_CANCELLED (err u211))
(define-constant ERR_INSUFFICIENT_HARVEST (err u212))

;; Contract owner for admin functions
(define-constant CONTRACT_OWNER tx-sender)
(define-constant PLATFORM_FEE u25) ;; 2.5% platform fee
(define-constant MIN_CONTRACT_DURATION u52560) ;; ~1 season in blocks
(define-constant MAX_CONTRACT_DURATION u210240) ;; ~1 year in blocks
(define-constant DEPOSIT_PERCENTAGE u20) ;; 20% deposit required

;; Data variables
(define-data-var contract-counter uint u0)
(define-data-var total-volume uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var yieldbit-contract principal 'SP000000000000000000002Q6VF78)

;; Futures contract structure
(define-map futures-contracts
    uint
    {
        seller: principal,
        buyer: (optional principal),
        crop-type: (string-ascii 50),
        quantity: uint,
        price-per-unit: uint,
        total-value: uint,
        deposit-paid: uint,
        delivery-block: uint,
        created-block: uint,
        status: (string-ascii 20), ;; "open", "committed", "fulfilled", "cancelled", "defaulted"
        harvest-verified: bool
    }
)

;; Buyer commitments tracking
(define-map buyer-deposits
    {contract-id: uint, buyer: principal}
    uint
)

;; Contract performance metrics
(define-map seller-performance
    principal
    {
        contracts-created: uint,
        contracts-fulfilled: uint,
        total-volume: uint,
        reputation-score: uint
    }
)

(define-map buyer-performance
    principal
    {
        contracts-committed: uint,
        contracts-completed: uint,
        total-spent: uint,
        reputation-score: uint
    }
)

;; Read-only functions
(define-read-only (get-contract (contract-id uint))
    (map-get? futures-contracts contract-id)
)

(define-read-only (get-buyer-deposit (contract-id uint) (buyer principal))
    (map-get? buyer-deposits {contract-id: contract-id, buyer: buyer})
)

(define-read-only (get-seller-performance (seller principal))
    (map-get? seller-performance seller)
)

(define-read-only (get-buyer-performance (buyer principal))
    (map-get? buyer-performance buyer)
)

(define-read-only (get-contract-counter)
    (ok (var-get contract-counter))
)

(define-read-only (get-total-volume)
    (ok (var-get total-volume))
)

(define-read-only (get-platform-stats)
    (ok {
        total-volume: (var-get total-volume),
        total-fees: (var-get total-fees-collected),
        active-contracts: (var-get contract-counter)
    })
)

;; Simple verification - in production would integrate with Yieldbit contract
(define-private (is-registered-farmer (farmer principal))
    true ;; Placeholder - assume all farmers are registered for now
)

;; Public functions

;; Create a new futures contract
(define-public (create-futures-contract 
    (crop-type (string-ascii 50)) 
    (quantity uint) 
    (price-per-unit uint) 
    (delivery-block uint))
    (let ((seller tx-sender)
          (current-block stacks-block-height)
          (new-contract-id (+ (var-get contract-counter) u1))
          (total-value (* quantity price-per-unit))
          (required-deposit (/ (* total-value DEPOSIT_PERCENTAGE) u100)))
        
        ;; Validations
        (asserts! (is-registered-farmer seller) ERR_NOT_AUTHORIZED)
        (asserts! (> quantity u0) ERR_INVALID_AMOUNT)
        (asserts! (> price-per-unit u0) ERR_INVALID_PRICE)
        (asserts! (> delivery-block (+ current-block MIN_CONTRACT_DURATION)) ERR_INVALID_DELIVERY_DATE)
        (asserts! (< delivery-block (+ current-block MAX_CONTRACT_DURATION)) ERR_INVALID_DELIVERY_DATE)
        
        ;; Transfer deposit from seller (simplified for demo)
        ;; In production, would transfer YBT tokens from seller to contract
        ;; (try! (stx-transfer? required-deposit seller (as-contract tx-sender)))
        
        ;; Create contract
        (map-set futures-contracts new-contract-id {
            seller: seller,
            buyer: none,
            crop-type: crop-type,
            quantity: quantity,
            price-per-unit: price-per-unit,
            total-value: total-value,
            deposit-paid: required-deposit,
            delivery-block: delivery-block,
            created-block: current-block,
            status: "open",
            harvest-verified: false
        })
        
        ;; Update contract counter and seller performance
        (var-set contract-counter new-contract-id)
        (update-seller-performance seller u1 u0 total-value)
        
        (ok new-contract-id)
    )
)

;; Buyer commits to purchase
(define-public (commit-to-contract (contract-id uint))
    (let ((buyer tx-sender)
          (contract-data (unwrap! (get-contract contract-id) ERR_CONTRACT_NOT_FOUND)))
        
        ;; Validations
        (asserts! (is-eq (get status contract-data) "open") ERR_CONTRACT_FULFILLED)
        (asserts! (< stacks-block-height (get delivery-block contract-data)) ERR_CONTRACT_EXPIRED)
        (asserts! (is-none (get buyer contract-data)) ERR_CONTRACT_FULFILLED)
        
        ;; Calculate required payment (full contract value)
        (let ((total-payment (get total-value contract-data))
              (platform-fee (/ (* total-payment PLATFORM_FEE) u1000)))
            
            ;; Transfer payment from buyer to contract (simplified for demo)
            ;; In production, would transfer YBT tokens from buyer to contract
            ;; (try! (stx-transfer? total-payment buyer (as-contract tx-sender)))
            
            ;; Update contract with buyer
            (map-set futures-contracts contract-id 
                (merge contract-data {
                    buyer: (some buyer),
                    status: "committed"
                }))
            
            ;; Record buyer deposit
            (map-set buyer-deposits {contract-id: contract-id, buyer: buyer} total-payment)
            
            ;; Update buyer performance
            (update-buyer-performance buyer u1 u0 total-payment)
            
            (ok true)
        )
    )
)

;; Fulfill contract after harvest verification
(define-public (fulfill-contract (contract-id uint) (harvest-amount uint))
    (let ((seller tx-sender)
          (contract-data (unwrap! (get-contract contract-id) ERR_CONTRACT_NOT_FOUND)))
        
        ;; Validations
        (asserts! (is-eq seller (get seller contract-data)) ERR_NOT_SELLER)
        (asserts! (is-eq (get status contract-data) "committed") ERR_CONTRACT_NOT_FOUND)
        (asserts! (>= harvest-amount (get quantity contract-data)) ERR_INSUFFICIENT_HARVEST)
        
        ;; Verify harvest exists in main contract
        ;; (let ((current-season (unwrap-panic (contract-call? (var-get yieldbit-contract) get-current-season))))
        ;; In real implementation, would verify specific harvest record
        ;; For now, assuming farmer has verified harvest
        
        (let ((buyer-principal (unwrap-panic (get buyer contract-data)))
              (contract-value (get total-value contract-data))
              (seller-deposit (get deposit-paid contract-data))
              (platform-fee (/ (* contract-value PLATFORM_FEE) u1000))
              (seller-payout (- (+ contract-value seller-deposit) platform-fee))
              )
            
            ;; Transfer payment to seller (simplified for demo)
            ;; In production, would transfer YBT tokens from contract to seller
            ;; (try! (as-contract (stx-transfer? seller-payout (as-contract tx-sender) seller)))
            
            ;; Update contract status
            (map-set futures-contracts contract-id 
                (merge contract-data {
                    status: "fulfilled",
                    harvest-verified: true
                }))
            
            ;; Update performance metrics
            (update-seller-performance seller u0 u1 contract-value)
            (update-buyer-performance buyer-principal u0 u1 u0)
            
            ;; Update platform stats
            (var-set total-volume (+ (var-get total-volume) contract-value))
            (var-set total-fees-collected (+ (var-get total-fees-collected) platform-fee))
            
            (ok seller-payout)
        )
    )
)

;; Cancel contract (only if no buyer committed)
(define-public (cancel-contract (contract-id uint))
    (let ((seller tx-sender)
          (contract-data (unwrap! (get-contract contract-id) ERR_CONTRACT_NOT_FOUND)))
        
        ;; Validations
        (asserts! (is-eq seller (get seller contract-data)) ERR_NOT_SELLER)
        (asserts! (is-eq (get status contract-data) "open") ERR_CONTRACT_FULFILLED)
        (asserts! (is-none (get buyer contract-data)) ERR_CONTRACT_FULFILLED)
        
        ;; Return deposit to seller (simplified for demo)
        ;; In production, would return YBT tokens from contract to seller
        ;; (let ((seller-deposit (get deposit-paid contract-data)))
        ;;     (try! (as-contract (stx-transfer? seller-deposit (as-contract tx-sender) seller)))
        ;; )
        
        ;; Update contract status
        (map-set futures-contracts contract-id 
            (merge contract-data {status: "cancelled"}))
        
        (ok true)
    )
)

;; Handle contract default (buyer can claim if delivery not made)
(define-public (claim-default (contract-id uint))
    (let ((buyer tx-sender)
          (contract-data (unwrap! (get-contract contract-id) ERR_CONTRACT_NOT_FOUND)))
        
        ;; Validations
        (asserts! (is-eq (some buyer) (get buyer contract-data)) ERR_NOT_BUYER)
        (asserts! (is-eq (get status contract-data) "committed") ERR_CONTRACT_FULFILLED)
        (asserts! (> stacks-block-height (get delivery-block contract-data)) ERR_HARVEST_NOT_READY)
        
        ;; Buyer gets full refund plus seller's deposit as penalty (simplified for demo)
        ;; In production, would transfer YBT tokens from contract to buyer
        ;; (let ((buyer-payment (get total-value contract-data))
        ;;       (seller-deposit (get deposit-paid contract-data))
        ;;       (total-refund (+ buyer-payment seller-deposit)))
        ;;     (try! (as-contract (stx-transfer? total-refund (as-contract tx-sender) buyer)))
        ;; )
        
        ;; Update contract status
        (map-set futures-contracts contract-id 
            (merge contract-data {status: "defaulted"}))
        
        ;; Penalize seller performance
        (let ((seller-perf (default-to {contracts-created: u0, contracts-fulfilled: u0, total-volume: u0, reputation-score: u100}
                                      (get-seller-performance (get seller contract-data)))))
            (map-set seller-performance (get seller contract-data)
                (merge seller-perf {reputation-score: (max u0 (- (get reputation-score seller-perf) u20))}))
        )
        
        (ok true)
    )
)

;; Private helper functions
(define-private (update-seller-performance (seller principal) (created uint) (fulfilled uint) (volume uint))
    (let ((current-perf (default-to {contracts-created: u0, contracts-fulfilled: u0, total-volume: u0, reputation-score: u100}
                                   (get-seller-performance seller))))
        (map-set seller-performance seller {
            contracts-created: (+ (get contracts-created current-perf) created),
            contracts-fulfilled: (+ (get contracts-fulfilled current-perf) fulfilled),
            total-volume: (+ (get total-volume current-perf) volume),
            reputation-score: (if (> fulfilled u0) 
                                (min u100 (+ (get reputation-score current-perf) u5))
                                (get reputation-score current-perf))
        })
    )
)

(define-private (update-buyer-performance (buyer principal) (committed uint) (completed uint) (spent uint))
    (let ((current-perf (default-to {contracts-committed: u0, contracts-completed: u0, total-spent: u0, reputation-score: u100}
                                   (get-buyer-performance buyer))))
        (map-set buyer-performance buyer {
            contracts-committed: (+ (get contracts-committed current-perf) committed),
            contracts-completed: (+ (get contracts-completed current-perf) completed),
            total-spent: (+ (get total-spent current-perf) spent),
            reputation-score: (if (> completed u0)
                                (min u100 (+ (get reputation-score current-perf) u3))
                                (get reputation-score current-perf))
        })
    )
)

(define-private (max (a uint) (b uint))
    (if (>= a b) a b)
)

(define-private (min (a uint) (b uint))
    (if (<= a b) a b)
)

;; Set Yieldbit contract principal (admin only)
(define-public (set-yieldbit-contract (new-contract principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set yieldbit-contract new-contract)
        (ok true)
    )
)
