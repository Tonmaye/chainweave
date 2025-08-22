;; Stake Manager Contract for Oracle Operators
;; Handles staking, unstaking, delegation, and reward distribution

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-INSUFFICIENT-BALANCE u101)
(define-constant ERR-ALREADY_STAKED u102)
(define-constant ERR-INVALID-AMOUNT u102)
(define-constant ERR-OPERATOR-NOT-FOUND u103)
(define-constant ERR-ALREADY-STAKED u104)
(define-constant ERR-NOT-STAKED u105)
(define-constant ERR-UNSTAKING-PERIOD-ACTIVE u106)
(define-constant ERR-ALREADY-DELEGATED u107)
(define-constant ERR-DELEGATION-NOT-FOUND u108)
(define-constant ERR-SELF-DELEGATION u109)
(define-constant ERR-OPERATOR-SUSPENDED u110)
(define-constant ERR-MINIMUM_STAKE_NOT_MET u111)
(define-constant ERR-SLASHING-IN-PROGRESS u112)
(define-constant ERR-REWARD-CALCULATION-FAILED u113)
(define-constant ERR-INVALID-COMMISSION u114)
(define-constant ERR-COOLDOWN-PERIOD-ACTIVE u115)

;; Contract Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_OPERATOR_STAKE u100000000) ;; 100 STX minimum for operators
(define-constant MIN_DELEGATION_STAKE u1000000) ;; 1 STX minimum for delegation
(define-constant UNSTAKING_PERIOD u2016) ;; ~14 days in blocks
(define-constant REWARD_DISTRIBUTION_INTERVAL u144) ;; Daily reward distribution
(define-constant SLASHING_COOLDOWN u1008) ;; 7 days cooldown after slashing
(define-constant MAX_COMMISSION_RATE u5000) ;; 50% maximum commission
(define-constant PRECISION u1000000) ;; 6 decimal precision for calculations

;; Data Variables
(define-data-var total-staked uint u0)
(define-data-var total-operators uint u0)
(define-data-var total-delegators uint u0)
(define-data-var reward-pool-balance uint u0)
(define-data-var next-epoch uint u1)
(define-data-var epoch-duration uint u1008) ;; 7 days per epoch
(define-data-var last-epoch-end uint u0)

;; Oracle Operator Registry
(define-map oracle-operators
  principal ;; operator address
  {
    total-stake: uint,
    self-stake: uint,
    delegated-stake: uint,
    commission-rate: uint, ;; Basis points (100 = 1%)
    is-active: bool,
    is-suspended: bool,
    suspension-end: (optional uint),
    reputation-score: uint,
    total-rewards-earned: uint,
    slashing-history: uint,
    registered-at: uint,
    last-activity: uint,
    metadata-uri: (optional (string-ascii 200))
  }
)

;; Staker Information
(define-map stakers
  principal ;; staker address
  {
    staked-amount: uint,
    delegated-to: (optional principal),
    unstaking-amount: uint,
    unstaking-unlock-time: (optional uint),
    pending-rewards: uint,
    claimed-rewards: uint,
    last-reward-claim: uint,
    staked-at: uint,
    delegation-count: uint
  }
)

;; Delegation Records
(define-map delegations
  {delegator: principal, operator: principal}
  {
    amount: uint,
    delegated-at: uint,
    last-reward-claim: uint,
    accumulated-rewards: uint,
    is-active: bool
  }
)

;; Operator Delegation Lists
(define-map operator-delegators
  principal ;; operator
  (list 100 principal) ;; delegators
)

;; Reward Distribution Records
(define-map epoch-rewards
  uint ;; epoch number
  {
    total-rewards: uint,
    distributed-rewards: uint,
    operator-count: uint,
    total-stake-snapshot: uint,
    reward-per-stake: uint,
    distribution-completed: bool
  }
)

;; Slashing Records
(define-map slashing-events
  {operator: principal, epoch: uint}
  {
    slashed-amount: uint,
    reason: (string-ascii 100),
    slashed-at: uint,
    affected-delegators: uint,
    evidence-hash: (buff 32)
  }
)

;; Unstaking Queue
(define-map unstaking-queue
  {staker: principal, unlock-time: uint}
  {
    amount: uint,
    type: (string-ascii 20), ;; "stake" or "delegation"
    target-operator: (optional principal)
  }
)

;; Performance Metrics
(define-map operator-performance
  {operator: principal, epoch: uint}
  {
    data-feeds-provided: uint,
    uptime-percentage: uint,
    accuracy-score: uint,
    response-time: uint,
    disputes-raised: uint,
    disputes-resolved: uint
  }
)

;; Helper Functions

;; Calculate delegation rewards
(define-private (calculate-delegation-rewards (delegator principal) (operator principal))
  (match (map-get? delegations {delegator: delegator, operator: operator})
    delegation 
      (match (map-get? oracle-operators operator)
        op-info
          (let (
            (delegation-amount (get amount delegation))
            (total-operator-stake (get total-stake op-info))
            (commission-rate (get commission-rate op-info))
            (current-epoch (var-get next-epoch))
          )
            ;; Calculate proportional rewards minus commission
            (let (
              (base-rewards (/ (* delegation-amount u1000) total-operator-stake)) ;; Simplified calculation
              (commission (/ (* base-rewards commission-rate) u10000))
              (net-rewards (- base-rewards commission))
            )
              net-rewards
            )
          )
        u0
      )
    u0
  )
)

;; Update operator reputation based on performance
(define-private (update-reputation (operator principal) (performance-score uint))
  (match (map-get? oracle-operators operator)
    op-info
      (let (
        (current-reputation (get reputation-score op-info))
        ;; Simple reputation update: weighted average
        (new-reputation (/ (+ (* current-reputation u9) performance-score) u10))
      )
        (map-set oracle-operators operator 
          (merge op-info {reputation-score: new-reputation}))
        (ok new-reputation)
      )
    (err ERR-OPERATOR-NOT-FOUND)
  )
)

;; Check if operator meets minimum requirements
(define-private (validate-operator-requirements (operator principal))
  (match (map-get? oracle-operators operator)
    op-info
      (and 
        (>= (get total-stake op-info) MIN_OPERATOR_STAKE)
        (get is-active op-info)
        (not (get is-suspended op-info))
      )
    false
  )
)

;; Read-only Functions

;; Get operator information
(define-read-only (get-operator-info (operator principal))
  (map-get? oracle-operators operator)
)

;; Get staker information
(define-read-only (get-staker-info (staker principal))
  (map-get? stakers staker)
)

;; Get delegation information
(define-read-only (get-delegation-info (delegator principal) (operator principal))
  (map-get? delegations {delegator: delegator, operator: operator})
)

;; Get operator's delegators
(define-read-only (get-operator-delegators (operator principal))
  (default-to (list) (map-get? operator-delegators operator))
)

;; Calculate pending rewards for staker
(define-read-only (get-pending-rewards (staker principal))
  (match (get-staker-info staker)
    staker-info
      (match (get delegated-to staker-info)
        operator (calculate-delegation-rewards staker operator)
        ;; Direct staker rewards calculation would go here
        u0
      )
    u0
  )
)

;; Get operator performance metrics
(define-read-only (get-operator-performance (operator principal) (epoch uint))
  (map-get? operator-performance {operator: operator, epoch: epoch})
)

;; Get total staking statistics
(define-read-only (get-staking-stats)
  {
    total-staked: (var-get total-staked),
    total-operators: (var-get total-operators),
    total-delegators: (var-get total-delegators),
    reward-pool-balance: (var-get reward-pool-balance),
    current-epoch: (var-get next-epoch),
    epoch-duration: (var-get epoch-duration)
  }
)

;; Public Functions

;; Register as Oracle Operator
(define-public (register-operator 
    (initial-stake uint)
    (commission-rate uint)
    (metadata-uri (optional (string-ascii 200))))
  (let (
    (current-block stacks-block-height)
  )
    (begin
      ;; Validate inputs
      (asserts! (>= initial-stake MIN_OPERATOR_STAKE) (err ERR-MINIMUM_STAKE_NOT_MET))
      (asserts! (<= commission-rate MAX_COMMISSION_RATE) (err ERR-INVALID-COMMISSION))
      (asserts! (is-none (get-operator-info tx-sender)) (err ERR-ALREADY_STAKED))
      
      ;; Transfer stake to contract
      (try! (stx-transfer? initial-stake tx-sender (as-contract tx-sender)))
      
      ;; Register operator
      (map-set oracle-operators tx-sender {
        total-stake: initial-stake,
        self-stake: initial-stake,
        delegated-stake: u0,
        commission-rate: commission-rate,
        is-active: true,
        is-suspended: false,
        suspension-end: none,
        reputation-score: u100, ;; Start with 100% reputation
        total-rewards-earned: u0,
        slashing-history: u0,
        registered-at: current-block,
        last-activity: current-block,
        metadata-uri: metadata-uri
      })
      
      ;; Update global stats
      (var-set total-staked (+ (var-get total-staked) initial-stake))
      (var-set total-operators (+ (var-get total-operators) u1))
      
      (ok tx-sender)
    )
  )
)

;; Stake additional tokens to existing operator
(define-public (add-stake (amount uint))
  (let (
    (operator-info (unwrap! (get-operator-info tx-sender) (err ERR-OPERATOR-NOT-FOUND)))
  )
    (begin
      ;; Validate amount
      (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
      (asserts! (not (get is-suspended operator-info)) (err ERR-OPERATOR-SUSPENDED))
      
      ;; Transfer additional stake
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update operator stake
      (map-set oracle-operators tx-sender 
        (merge operator-info {
          total-stake: (+ (get total-stake operator-info) amount),
          self-stake: (+ (get self-stake operator-info) amount)
        }))
      
      ;; Update global stats
      (var-set total-staked (+ (var-get total-staked) amount))
      
      (ok amount)
    )
  )
)

;; Delegate stake to an operator
(define-public (delegate-stake (operator principal) (amount uint))
  (let (
    (operator-info (unwrap! (get-operator-info operator) (err ERR-OPERATOR-NOT-FOUND)))
    (existing-delegation (map-get? delegations {delegator: tx-sender, operator: operator}))
    (staker-info (default-to 
      {staked-amount: u0, delegated-to: none, unstaking-amount: u0, unstaking-unlock-time: none,
       pending-rewards: u0, claimed-rewards: u0, last-reward-claim: u0, staked-at: u0, delegation-count: u0}
      (get-staker-info tx-sender)))
    (current-block stacks-block-height)
    (delegators-list (default-to (list) (map-get? operator-delegators operator)))
  )
    (begin
      ;; Validate delegation
      (asserts! (not (is-eq tx-sender operator)) (err ERR-SELF-DELEGATION))
      (asserts! (>= amount MIN_DELEGATION_STAKE) (err ERR-INVALID-AMOUNT))
      (asserts! (validate-operator-requirements operator) (err ERR-OPERATOR-SUSPENDED))
      
      ;; Transfer stake to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update or create delegation
      (match existing-delegation
        delegation 
          ;; Update existing delegation
          (map-set delegations {delegator: tx-sender, operator: operator}
            (merge delegation {
              amount: (+ (get amount delegation) amount),
              last-reward-claim: current-block
            }))
        ;; Create new delegation
        (begin
          (map-set delegations {delegator: tx-sender, operator: operator} {
            amount: amount,
            delegated-at: current-block,
            last-reward-claim: current-block,
            accumulated-rewards: u0,
            is-active: true
          })
          
          ;; Add delegator to operator's list
          (map-set operator-delegators operator 
            (unwrap! (as-max-len? (append delegators-list tx-sender) u100) (err ERR-INVALID-AMOUNT)))
        )
      )
      
      ;; Update staker info
      (map-set stakers tx-sender 
        (merge staker-info {
          staked-amount: (+ (get staked-amount staker-info) amount),
          delegated-to: (some operator),
          staked-at: current-block,
          delegation-count: (+ (get delegation-count staker-info) u1)
        }))
      
      ;; Update operator's delegated stake
      (map-set oracle-operators operator 
        (merge operator-info {
          total-stake: (+ (get total-stake operator-info) amount),
          delegated-stake: (+ (get delegated-stake operator-info) amount)
        }))
      
      ;; Update global stats
      (var-set total-staked (+ (var-get total-staked) amount))
      (if (is-eq (get delegation-count staker-info) u0)
        (var-set total-delegators (+ (var-get total-delegators) u1))
        true
      )
      
      (ok amount)
    )
  )
)

;; Initiate unstaking process
(define-public (initiate-unstaking (amount uint) (from-operator (optional principal)))
  (let (
    (staker-info (unwrap! (get-staker-info tx-sender) (err ERR-NOT-STAKED)))
    (current-block stacks-block-height)
    (unlock-time (+ current-block UNSTAKING_PERIOD))
  )
    (begin
      ;; Validate unstaking amount
      (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
      (asserts! (<= amount (get staked-amount staker-info)) (err ERR-INSUFFICIENT-BALANCE))
      
      ;; Check if unstaking from specific operator
      (match from-operator
        operator 
          (let (
            (delegation (unwrap! (get-delegation-info tx-sender operator) (err ERR-DELEGATION-NOT-FOUND)))
            (operator-info (unwrap! (get-operator-info operator) (err ERR-OPERATOR-NOT-FOUND)))
          )
            (begin
              ;; Validate delegation amount
              (asserts! (<= amount (get amount delegation)) (err ERR-INSUFFICIENT-BALANCE))
              
              ;; Update delegation
              (let ((remaining-amount (- (get amount delegation) amount)))
                (if (is-eq remaining-amount u0)
                  ;; Remove delegation entirely
                  (map-set delegations {delegator: tx-sender, operator: operator}
                    (merge delegation {is-active: false}))
                  ;; Reduce delegation amount
                  (map-set delegations {delegator: tx-sender, operator: operator}
                    (merge delegation {amount: remaining-amount}))
                )
              )
              
              ;; Update operator's delegated stake
              (map-set oracle-operators operator 
                (merge operator-info {
                  total-stake: (- (get total-stake operator-info) amount),
                  delegated-stake: (- (get delegated-stake operator-info) amount)
                }))
            )
          )
        ;; Direct stake unstaking (operator unstaking their own stake)
        (let (
          (operator-info (unwrap! (get-operator-info tx-sender) (err ERR-OPERATOR-NOT-FOUND)))
        )
          (begin
            (asserts! (<= amount (get self-stake operator-info)) (err ERR-INSUFFICIENT-BALANCE))
            
            ;; Ensure minimum stake remains
            (asserts! (>= (- (get self-stake operator-info) amount) MIN_OPERATOR_STAKE) 
                     (err ERR-MINIMUM_STAKE_NOT_MET))
            
            ;; Update operator stake
            (map-set oracle-operators tx-sender 
              (merge operator-info {
                total-stake: (- (get total-stake operator-info) amount),
                self-stake: (- (get self-stake operator-info) amount)
              }))
          )
        )
      )
      
      ;; Update staker info
      (map-set stakers tx-sender 
        (merge staker-info {
          staked-amount: (- (get staked-amount staker-info) amount),
          unstaking-amount: (+ (get unstaking-amount staker-info) amount),
          unstaking-unlock-time: (some unlock-time)
        }))
      
      ;; Add to unstaking queue
      (map-set unstaking-queue {staker: tx-sender, unlock-time: unlock-time} {
        amount: amount,
        type: (if (is-some from-operator) "delegation" "stake"),
        target-operator: from-operator
      })
      
      ;; Update global stats
      (var-set total-staked (- (var-get total-staked) amount))
      
      (ok unlock-time)
    )
  )
)

;; Complete unstaking after waiting period
(define-public (complete-unstaking)
  (let (
    (staker-info (unwrap! (get-staker-info tx-sender) (err ERR-NOT-STAKED)))
    (current-block stacks-block-height)
    (unlock-time (unwrap! (get unstaking-unlock-time staker-info) (err ERR-UNSTAKING-PERIOD-ACTIVE)))
  )
    (begin
      ;; Check if unstaking period has passed
      (asserts! (>= current-block unlock-time) (err ERR-UNSTAKING-PERIOD-ACTIVE))
      
      (let ((unstaking-amount (get unstaking-amount staker-info)))
        ;; Transfer unstaked tokens back to user
        (try! (as-contract (stx-transfer? unstaking-amount tx-sender tx-sender)))
        
        ;; Update staker info
        (map-set stakers tx-sender 
          (merge staker-info {
            unstaking-amount: u0,
            unstaking-unlock-time: none
          }))
        
        ;; Remove from unstaking queue
        (map-delete unstaking-queue {staker: tx-sender, unlock-time: unlock-time})
        
        (ok unstaking-amount)
      )
    )
  )
)

;; Claim accumulated rewards
(define-public (claim-rewards (operator (optional principal)))
  (let (
    (current-block stacks-block-height)
  )
    (match operator
      op ;; Claiming delegation rewards
        (let (
          (delegation (unwrap! (get-delegation-info tx-sender op) (err ERR-DELEGATION-NOT-FOUND)))
          (pending-rewards (calculate-delegation-rewards tx-sender op))
        )
          (if (> pending-rewards u0)
            (begin
              ;; Transfer rewards
              (try! (as-contract (stx-transfer? pending-rewards tx-sender tx-sender)))
              
              ;; Update delegation
              (map-set delegations {delegator: tx-sender, operator: op}
                (merge delegation {
                  last-reward-claim: current-block,
                  accumulated-rewards: (+ (get accumulated-rewards delegation) pending-rewards)
                }))
              
              (ok pending-rewards)
            )
            (ok u0)
          )
        )
      ;; Claiming operator rewards
      (let (
        (operator-info (unwrap! (get-operator-info tx-sender) (err ERR-OPERATOR-NOT-FOUND)))
        ;; Simplified operator reward calculation
        (operator-rewards (/ (get total-stake operator-info) u1000))
      )
        (if (> operator-rewards u0)
          (begin
            ;; Transfer operator rewards
            (try! (as-contract (stx-transfer? operator-rewards tx-sender tx-sender)))
            
            ;; Update operator rewards
            (map-set oracle-operators tx-sender 
              (merge operator-info {
                total-rewards-earned: (+ (get total-rewards-earned operator-info) operator-rewards),
                last-activity: current-block
              }))
            
            (ok operator-rewards)
          )
          (ok u0)
        )
      )
    )
  )
)

;; Update operator commission rate
(define-public (update-commission-rate (new-rate uint))
  (let (
    (operator-info (unwrap! (get-operator-info tx-sender) (err ERR-OPERATOR-NOT-FOUND)))
  )
    (begin
      ;; Validate commission rate
      (asserts! (<= new-rate MAX_COMMISSION_RATE) (err ERR-INVALID-COMMISSION))
      (asserts! (not (get is-suspended operator-info)) (err ERR-OPERATOR-SUSPENDED))
      
      ;; Update commission rate
      (map-set oracle-operators tx-sender 
        (merge operator-info {commission-rate: new-rate}))
      
      (ok new-rate)
    )
  )
)

;; Admin Functions

;; Slash operator for misbehavior
(define-public (slash-operator 
    (operator principal) 
    (slash-amount uint) 
    (reason (string-ascii 100))
    (evidence-hash (buff 32)))
  (let (
    (operator-info (unwrap! (get-operator-info operator) (err ERR-OPERATOR-NOT-FOUND)))
    (current-epoch (var-get next-epoch))
    (current-block stacks-block-height)
  )
    (begin
      ;; Only contract owner can slash
      (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR-NOT-AUTHORIZED))
      
      ;; Validate slash amount
      (asserts! (<= slash-amount (get total-stake operator-info)) (err ERR-INVALID-AMOUNT))
      
      ;; Record slashing event
      (map-set slashing-events {operator: operator, epoch: current-epoch} {
        slashed-amount: slash-amount,
        reason: reason,
        slashed-at: current-block,
        affected-delegators: (len (get-operator-delegators operator)),
        evidence-hash: evidence-hash
      })
      
      ;; Update operator info
      (map-set oracle-operators operator 
        (merge operator-info {
          total-stake: (- (get total-stake operator-info) slash-amount),
          is-suspended: true,
          suspension-end: (some (+ current-block SLASHING_COOLDOWN)),
          slashing-history: (+ (get slashing-history operator-info) u1),
          reputation-score: (/ (get reputation-score operator-info) u2) ;; Halve reputation
        }))
      
      ;; Update global stats
      (var-set total-staked (- (var-get total-staked) slash-amount))
      
      ;; Add slashed amount to reward pool
      (var-set reward-pool-balance (+ (var-get reward-pool-balance) slash-amount))
      
      (ok slash-amount)
    )
  )
)

;; Distribute rewards to operators and delegators
(define-public (distribute-epoch-rewards (total-rewards uint))
  (let (
    (current-epoch (var-get next-epoch))
    (current-block stacks-block-height)
    (total-stake-snapshot (var-get total-staked))
  )
    (begin
      ;; Only contract owner can distribute rewards
      (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR-NOT-AUTHORIZED))
      (asserts! (> total-rewards u0) (err ERR-INVALID-AMOUNT))
      
      ;; Transfer rewards to contract
      (try! (stx-transfer? total-rewards tx-sender (as-contract tx-sender)))
      
      ;; Record epoch rewards
      (map-set epoch-rewards current-epoch {
        total-rewards: total-rewards,
        distributed-rewards: u0,
        operator-count: (var-get total-operators),
        total-stake-snapshot: total-stake-snapshot,
        reward-per-stake: (if (> total-stake-snapshot u0) 
                          (/ (* total-rewards PRECISION) total-stake-snapshot) 
                          u0),
        distribution-completed: false
      })
      
      ;; Update reward pool
      (var-set reward-pool-balance (+ (var-get reward-pool-balance) total-rewards))
      
      ;; Advance epoch
      (var-set next-epoch (+ current-epoch u1))
      (var-set last-epoch-end current-block)
      
      (ok current-epoch)
    )
  )
)

;; Suspend/unsuspend operator
(define-public (set-operator-suspension (operator principal) (suspended bool) (duration (optional uint)))
  (let (
    (operator-info (unwrap! (get-operator-info operator) (err ERR-OPERATOR-NOT-FOUND)))
    (current-block stacks-block-height)
  )
    (begin
      ;; Only contract owner can suspend
      (asserts! (is-eq tx-sender CONTRACT_OWNER) (err ERR-NOT-AUTHORIZED))
      
      (map-set oracle-operators operator 
        (merge operator-info {
          is-suspended: suspended,
          suspension-end: (if suspended 
                           (match duration 
                             dur (some (+ current-block dur))
                             (some (+ current-block SLASHING_COOLDOWN)))
                           none)
        }))
      
      (ok suspended)
    )
  )
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-staked: (var-get total-staked),
    total-operators: (var-get total-operators),
    total-delegators: (var-get total-delegators),
    reward-pool-balance: (var-get reward-pool-balance),
    current-epoch: (var-get next-epoch),
    contract-balance: (stx-get-balance (as-contract tx-sender))
  }
)