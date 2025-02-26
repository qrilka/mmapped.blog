#lang pollen

◊(define-meta title "ckBTC internals: event log")
◊(define-meta keywords "ic,canisters")
◊(define-meta summary "Like event sourcing, but in a canister.")
◊(define-meta doc-publish-date "2023-05-01")
◊(define-meta doc-updated-date "2023-05-01")

◊section{
◊section-title["intro"]{Introduction}
◊p{
  The ◊a[#:href "https://medium.com/dfinity/chain-key-bitcoin-a-decentralized-bitcoin-twin-ceb8f4ddf95e"]{chain-key Bitcoin} (ckBTC) project became ◊a[#:href "https://twitter.com/dfinity/status/1642887821731004418"]{publicly available} on April 3, 2023.
  The ckBTC ◊em{minter} smart contract is the most novel part of the product responsible for converting Bitcoin to ckBTC tokens and back.
  This contract features several design choices that some developers might find insightful.
  This article describes how the ckBTC minter, which I will further refer to as ◊quoted{the minter}, organizes its storage.
}
}

◊section{
◊section-title["motivation"]{Motivation}
◊p{
  The minter is a complicated system that must maintain a lot of state variables:
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊a[#:href "https://en.wikipedia.org/wiki/Unspent_transaction_output"]{Unspent Transaction Outputs} (◊smallcaps{utxo}s) the minter owns on the Bitcoin network, indexed and sliced in various ways (by account, state, etc.).
  }
  ◊li{
    ckBTC to Bitcoin conversion requests, indexed by state and the arrival time.
  }
  ◊li{
    Pending Bitcoin transactions fulfilling the withdrawal requests.
  }
  ◊li{
    Fees owed to the ◊a[#:href "https://thepaypers.com/expert-opinion/know-your-transaction-kyt-the-key-to-combating-transaction-laundering--1246231"]{Know Your Transaction} (KYT) service providers.
  }
}

◊p{
  How to preserve this state across canister upgrades?
}

◊p{
  On the one hand, we◊sidenote["sn-we"]{Here and further, I'll use ◊quoted{we} to indicate the ckBTC development team.} didn't want to ◊a[#:href "/posts/11-ii-stable-memory.html#conventional-memory-management"]{marshal the entire state} through stable memory.
  We preferred to avoid pre-upgrade hooks altogether to eliminate the possibility that the minter becomes ◊a[#:href "/posts/01-effective-rust-canisters.html#upgrade-hook-panics"]{non-upgradable} due to a bug in the hook.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-traditional-upgrade"]{
    The traditional canister state management scheme.
    The canister applies ◊em{state transitions} ◊math{T◊sub{i}} to its states ◊math{S◊sub{i}} on the Wasm heap (designated with a circle) and marshals the state through stable memory on upgrades.
    This approach requires state representations to be backward compatible only within the scope of a single upgrade.
    The number of instructions needed for an upgrade is proportional to the state size.
  }
  ◊(embed-svg "images/19-traditional-upgrade.svg")
}

◊p{
  On the other hand, we didn't want to invest much time crafting an efficient data layout using the ◊code-ref["/posts/14-stable-structures.html"]{stable-structures} package.
  All our data structures were in flux; we didn't want to commit to a specific representation too early.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-stable-memory"]{
    Managing the canister state in directly stable memory.
    The canister applies ◊em{state transitions} ◊math{T◊sub{i}} to its states ◊math{S◊sub{i}} persisted in stable memory.
    This approach trades the flexibility of state representation for the predictability and safety of upgrades.
    The number of instructions needed for an upgrade is constant.
  }
  ◊(embed-svg "images/19-stable-memory-only.svg")
}

◊p{
  Luckily, the problem has peculiarities we could exploit.
  All of the minter's state modifications are expensive: minting ckBTC requires the caller to invest at least a few dollars into a transaction on the Bitcoin network.
  Withdrawal requests involve paying transaction fees.
  In addition, the volume of modifications is relatively low because of the Bitcoin network limitations.
}
}

◊section{
◊section-title["solution"]{Solution}

◊p{
  The minter employs the ◊a[#:href "https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing"]{event sourcing} pattern to organize its stable storage.
  It declares a single stable data structure: an append-only ◊a[#:href "https://sourcegraph.com/github.com/dfinity/ic@5c0af72426c7eca863201c4853cb18dab504a140/-/blob/rs/bitcoin/ckbtc/minter/src/storage.rs?L21"]{log} of events affecting the canister state.
}

◊p{
  Each time the minter modifies its state, it appends an event to the log.
  The event carries enough context to allow us to reproduce the state modification later.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-event-log-upgrade"]{
    Managing the canister state using the event log.
    As in the traditional scheme, the canister applies state transitions ◊math{T◊sub{i}} to its states on the Wasm heap, but it also records the state transitions to an append-only log data structure in stable memory.
    The ◊code{post_upgrade} hook applies all recorded transitions to the initial state to recompute the last snapshot.
    The number of instructions required for an upgrade is proporional to the number of state transitions.
    Note the absense of ◊code{pre_upgrade} hook.
  }
  ◊(embed-svg "images/19-event-log-upgrade.svg")
}

◊p{
  On upgrade, the minter starts from an empty state and replays events from the log.
  This approach might sound inefficient, but it works great in our case:
}

◊ul[#:class "arrows"]{
  ◊li{
    The number of events is relatively low because most involve a transfer on the Bitcoin network.
  }
  ◊li{
    The cost of replaying an event is low.
    Replaying twenty-five thousand events consumes less than one billion instructions, which is cheaper than submitting a single Bitcoin transaction.
  }
  ◊li{
    We can pause and resume the replay process to spread the work across multiple executions if the number of events goes out of hand.
  }
}

◊p{
  Furthermore, the event-sourcing approach offers additional benefits beyond the original motivation:
}

◊ul[#:class "arrows"]{
  ◊li{
    The event log provides an audit trace for all state modifications, making the system more transparent and easier to debug.
  }
  ◊li{
    The event log is easy to replicate to other canisters and off-chain.
    It's a perfect incremental backup solution.
  }
  ◊li{
    We can change the state representation without worrying about backward compatibility.
    Only the event types stored in stable memory must be backward-compatible.
  }
}

◊subsection-title["what-is-an-event"]{What is an event?}

◊p{
  One crucial aspect of the design is the log record's content.
}

◊p{
  The brute-force approach is to record as events the arguments of all incoming update calls, all outgoing inter-canister calls, and the corresponding replies.
  This approach might work, but it takes a lot of work to implement and requires a complicated log replay procedure.
}

◊p{
  Differentiating between ◊em{requests} (sometimes called ◊em{commands}) and ◊em{events} is a better option.
  ◊em{Requests} come from the outside world (ingress messages, replies, timers) and ◊em{might} trigger canister state changes.
  ◊em{Events} record effects of productive requests on the canister state.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-request-event"]{
    Requests such as ingress messages come from the outside world and can trigger zero or more events.
  }
  ◊(embed-svg "images/19-request-event.svg")
}

◊p{
  Let's use the minter's ◊code-ref["https://sourcegraph.com/github.com/dfinity/ic@1cbf1f39d31bc426c1e15b073c4ac86d75056bb2/-/blob/rs/bitcoin/ckbtc/minter/ckbtc_minter.did?L253"]{update_balance} flow as an example:
}

◊ol-circled{
  ◊li{
    A user calls the ◊code-ref["https://sourcegraph.com/github.com/dfinity/ic@1cbf1f39d31bc426c1e15b073c4ac86d75056bb2/-/blob/rs/bitcoin/ckbtc/minter/ckbtc_minter.did?L246"]{get_btc_address} the obtains a Bitcoin address corresponding to the user's ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec#principal"]{principal}.
  }
  ◊li{
    The user transfers Bitcoin to that address and waits for the transaction to get enough confirmations on the Bitcoin network (as of May 2023, the minter requires at least twelve confirmations).
  }
  ◊li{
    The user calls the ◊code{update_balance} endpoint on the minter.
  }
  ◊li{
    The minter fetches the list of its ◊smallcaps{utxo}s matching the user account from the ◊a[#:href "https://github.com/dfinity/bitcoin-canister"]{Bitcoin canister} and checks whether there are new items in the list.
  }
  ◊li{
    The minter mints ckBTC tokens on the ledger smart contract for each new ◊smallcaps{utxo} and reports the results to the user.
  }
}

◊p{
  That's a lot of interactions!
  Luckily, the only significant outcome of these actions is the minter acquiring a new ◊smallcaps{utxo}.
  That's our event type: ◊code{minted(utxo, account)}.
}

◊p{
  If any of the intermediate steps fails or there are no new ◊smallcaps{utxo}s in the list, the original request doesn't affect the minter state.
  Thus a malicious user cannot fill the minter's memory with unproductive events.
  Creating an event requires sending funds on the Bitcoin network, and that's a slow and expensive operation.
}

◊subsection-title["testing"]{Testing}

◊p{
  Event sourcing introduces new sources of bugs:
}
◊ul[#:class "arrows"]{
  ◊li{
   The programmer can implement the state transition logic but forget to emit the corresponding event.
  }
  ◊li{
   The event replay logic can produce different results than the original state update.
  }
}

◊p{
  We run our integration tests on a debug version of the minter canister to address this issue.
  After each update call, the debug version replays the log and compares the resulting state to the current canister state.
  If the log becomes inconsistent with the internal state, the test causing the divergence must fail.
}

◊figure{
◊marginnote["mn-debug-replay-log"]{
  Enabling self-checks in the debug canister version to ensure that the event log captures all state transitions.
}

◊source-code["rust"]{
#[update]
fn update_balance(arg: UpdateBalanceArg) -> UpdateBalanceResult {
    let result = update_balance_impl(arg);

    #[cfg(feature = "debug_version")]
    if let Err(msg) = replay_event_log().check_equals_to(&canister_state) {
      ic_cdk::trap(&msg);
    }

    result
}
}
}

◊p{
  The minter's self-checking feature helped us catch a few severe bugs early in development.
}
}

◊section{
◊section-title["resources"]{Resources}
◊ul[#:class "arrows"]{
  ◊li{
    Minter's ◊code-ref["https://sourcegraph.com/github.com/dfinity/ic@1cbf1f39d31bc426c1e15b073c4ac86d75056bb2/-/blob/rs/bitcoin/ckbtc/minter/src/state/eventlog.rs"]{eventlog.rs} module contains even type definitions and the log replay procedure.
  }
  ◊li{
    ◊a[#:href "https://www.oreilly.com/library/view/designing-data-intensive-applications/9781491903063/"]{◊quoted{Designing Data-Intensive Applications}} by Martin Kleppmann has an in-depth explanation of the event sourcing pattern (see Chapter 11: Stream Processing, p. 457).
  }
  ◊li{
    The ◊a[#:href "https://wiki.internetcomputer.org/wiki/Main_Page"]{Internet Computer Wiki} has a detailed article about ◊a[#:href "https://wiki.internetcomputer.org/wiki/Chain-key_Bitcoin#ckBTC_Minter"]{ckBTC minter}.
  }
}
}
