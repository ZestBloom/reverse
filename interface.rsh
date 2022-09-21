"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Active Reverse Auction (A1)
// Version: 1.2.7 - protect relay txn from rt
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------
// TODO calculate price change per second with more precision

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

import { rStake, rUnstake } from "@KinnFoundation/stake#stake-v0.1.11r0:interface.rsh";

import { Params, State as ReverseState, MContract } from "@KinnFoundation/reverse#reverse-v0.1.11r3:interface.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 9; // number of slots to distribute proceeds after sale

const FEE_MIN_ACCEPT = 8_000; // 0.008
const FEE_MIN_CONSTRUCT = 7_000; // 0.007
const FEE_MIN_RELAY = 20_000; // 0.019 + 0.001
const FEE_MIN_ACTIVE_BID = 1; // 1au
const FEE_MIN_ACTIVE_ACTIVATION = 1; // 1au

const ADDR_RESERVED_ACTIVE_BIDDER = 0;
const ADDR_RESERVED_CURATOR = 1;

// TYPES

const ActiveState = Struct([
  ["activeToken", Token],
  ["activeAmount", UInt],
  ["activeCtc", Contract],
]);

const State = Struct([
  ...Struct.fields(ReverseState(DIST_LENGTH)),
  ...Struct.fields(ActiveState)
]);

// FUNCS

/*
 * precision used in fixed point arithmetic
 */
const precision = 1000000; // 10 ^ 6

/*
 * calculate price based on seconds elapsed since reference secs
 */
const priceFunc =
  (secs) => (startPrice, floorPrice, referenceConcensusSecs, dk) =>
    max(
      floorPrice,
      ((diff) => {
        // REM if is lazy, ? is not lazy (startPrice - diff can underflow)
        // TODO ? is now lazy in a future version of reach, update later after reach-v0.1.11-rc7
        if (startPrice <= diff) {
          return floorPrice;
        } else {
          return startPrice - diff;
        }
      })(
        min(
          ((secs - referenceConcensusSecs) * dk) / precision,
          startPrice - floorPrice
        )
      )
    );

// calculate slope of line to determine price
const calc = (d, d2, p) => {
  const fD = fx(6)(Pos, d);
  const fD2 = fx(6)(Pos, d2);
  return fxdiv(fD, fD2, p);
};

/*
 * safePercent
 * recommended way of calculating percent of a number
 * where percentPrecision is like 10_000 and percentage is like 500, meaning 5%
 */
const safePercent = (amount, percentage, percentPrecision) =>
  UInt(
    (UInt256(amount) * UInt256(percentPrecision) * UInt256(percentage)) /
      UInt256(percentPrecision)
  );

// INTERACTS

const auctioneerInteract = {
  getParams: Fun([], Params(DIST_LENGTH)),
  signal: Fun([], Null),
};

const relayInteract = {};

// CONTRACT

export const Event = () => [];

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  ParticipantClass("Relay", relayInteract),
];

export const Views = () => [
  View({
    state: State,
  }),
];

export const Api = () => [
  API({
    touch: Fun([], Null),
    acceptOffer: Fun([Address], Null),
    cancel: Fun([], Null),
    bid: Fun([Contract], Null),
    bidCancel: Fun([], Null),
  }),
];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token, tok1: activeToken },
    [addr, _],
    [Auctioneer, Relay],
    [v],
    [a],
    _,
  ] = map;
  Auctioneer.only(() => {
    const {
      tokenAmount,
      startPrice,
      floorPrice,
      endSecs,
      addrs,
      distr,
      royaltyCap,
    } = declassify(interact.getParams());
  });

  // Step
  Auctioneer.publish(
    tokenAmount,
    startPrice,
    floorPrice,
    endSecs,
    addrs,
    distr,
    royaltyCap
  )
    .check(() => {
      check(tokenAmount > 0, "tokenAmount must be greater than 0");
      check(floorPrice > 0, "floorPrice must be greater than 0");
      check(
        floorPrice <= startPrice,
        "floorPrice must be less than or equal to startPrice"
      ); // fp < sp => auction, fp == sp => sale
      check(endSecs > 0, "endSecs must be greater than 0");
      check(
        distr.sum() <= royaltyCap,
        "distr sum must be less than or equal to royaltyCap"
      );
      check(
        royaltyCap == (10 * floorPrice) / 1000000,
        "royaltyCap must be 10x of floorPrice"
      );
    })
    .pay([
      amt + (FEE_MIN_CONSTRUCT + FEE_MIN_ACCEPT + FEE_MIN_RELAY) + SERIAL_VER,
      [tokenAmount, token],
      [FEE_MIN_ACTIVE_ACTIVATION, activeToken],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([
    amt + FEE_MIN_CONSTRUCT + SERIAL_VER,
    [FEE_MIN_ACTIVE_ACTIVATION, activeToken],
  ]).to(addr);

  Auctioneer.interact.signal();

  const distrTake = distr.sum();

  const referenceConcensusSecs = thisConsensusSecs();

  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;

  const initialState = {
    manager: Auctioneer,
    token,
    tokenAmount,
    currentPrice: startPrice,
    startPrice,
    floorPrice,
    closed: false,
    endSecs,
    priceChangePerSec: dk / precision,
    addrs,
    distr,
    royaltyCap: royaltyCap,
    who: Auctioneer,
    timestamp: referenceConcensusSecs,
    activeToken,
    activeAmount: 0,
    activeCtc: getContract(), // ref to self never used
  };

  // Step
  const [state, mctc] = parallelReduce([initialState, MContract.None()])
    .define(() => {
      v.state.set(State.fromObject(state));
    })
    // ACTIVE TOKEN BALANCE
    .invariant(
      implies(!state.closed, balance(token) == tokenAmount),
      "token balance accurate before closed"
    )
    .invariant(
      implies(state.closed, balance(token) == 0),
      "token balance accurate after closed"
    )
    // ACTIVE TOKEN BALANCE
    .invariant(balance(activeToken) == 0, "active token balance accurate")
    // BALANCE
    .invariant(
      implies(!state.closed, balance() == FEE_MIN_ACCEPT + FEE_MIN_RELAY),
      "balance accurate before close"
    )
    // REM missing invariant balance accurate after close
    .while(!state.closed)
    .paySpec([activeToken])
    // api: updates current price
    //  allows anybody to update price
    .api_(a.touch, () => {
      check(
        state.currentPrice >= floorPrice,
        "currentPrice must be greater than or equal to floorPrice"
      );
      return [
        (k) => {
          k(null);
          return [
            {
              ...state,
              currentPrice: priceFunc(thisConsensusSecs())(
                startPrice,
                floorPrice,
                referenceConcensusSecs,
                dk
              ),
            },
            mctc,
          ];
        },
      ];
    })
    // api: accepts offer
    // allows anybody but curator to accept offer
    //  transfers 1% to addr
    //  calculates proceeding take
    //  transfers reamining to seller
    //  transfers accept fee, diff, and token amount to buy
    //  transfers currator fee to curator
    .api_(a.acceptOffer, (cAddr) => {
      check(cAddr != this, "cannot accept offer as curator");
      return [
        [state.currentPrice, [0, activeToken]],
        (k) => {
          k(null);
          const bal = priceFunc(thisConsensusSecs())(
            startPrice,
            floorPrice,
            referenceConcensusSecs,
            dk
          );
          // expect state[cp] >= bal
          const diff = state.currentPrice - bal;
          const cent = bal / 100;
          const remaining = bal - cent;
          const partTake = remaining / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = remaining - proceedTake;
          transfer(cent).to(addr);
          transfer(sellerTake).to(Auctioneer);
          transfer([FEE_MIN_ACCEPT + diff, [tokenAmount, token]]).to(this);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              addrs: Array.set(state.addrs, ADDR_RESERVED_CURATOR, cAddr),
              distr: distr.map((d) => d * partTake),
              currentPrice: bal,
              who: this,
              closed: true,
            },
            mctc,
          ];
        },
      ];
    })
    // api: cancel
    // allows auctioneer to cancel auction
    //  transfers accept and curator fee and token(s) back to auctionee
    //  unstakes active token if any
    .api_(a.cancel, () => {
      check(this == Auctioneer, "only auctioneer can cancel");
      return [
        (k) => {
          k(null);
          transfer([FEE_MIN_ACCEPT, [tokenAmount, token]]).to(this);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              addrs: Array.set(
                state.addrs,
                ADDR_RESERVED_ACTIVE_BIDDER,
                Auctioneer
              ),
              closed: true,
              activeAmount: 0,
              activeCtc: getContract(),
            },
            MContract.None(),
          ];
        },
      ];
    })
    // api: bid
    // allows anybody to supersede the current bid
    //  transfer bid fee in network token and non-network token (active token) to addr
    //  unlock active token if any
    .api_(a.bid, (ctc) => {
      return [
        [0, [FEE_MIN_ACTIVE_BID, activeToken]],
        (k) => {
          k(null);
          transfer([0, [FEE_MIN_ACTIVE_BID, activeToken]]).to(addr);
          const { manager: r1Manager, tokenAmount: r1TokenAmount } = rStake(
            ctc,
            activeToken,
            state.activeAmount
          );
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              currentPrice: priceFunc(thisConsensusSecs())(
                startPrice,
                floorPrice,
                referenceConcensusSecs,
                dk
              ),
              addrs: Array.set(
                state.addrs,
                ADDR_RESERVED_ACTIVE_BIDDER,
                r1Manager
              ),
              activeAmount: r1TokenAmount,
              activeCtc: ctc,
            },
            MContract.Some(ctc),
          ];
        },
      ];
    })
    // api: bid cancel
    // allows the bidder to cancel their bid
    // unstakes active token if any
    .api_(a.bidCancel, () => {
      check(this == state.addrs[ADDR_RESERVED_ACTIVE_BIDDER], "only active bidder can cancel bid");
      return [
        (k) => {
          k(null);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              currentPrice: priceFunc(thisConsensusSecs())(
                startPrice,
                floorPrice,
                referenceConcensusSecs,
                dk
              ),
              addrs: Array.set(
                state.addrs,
                ADDR_RESERVED_ACTIVE_BIDDER,
                Auctioneer
              ),
              activeAmount: 0,
              activeCtc: getContract(),
            },
            MContract.None(),
          ];
        },
      ];
    })
    .timeout(false);
  commit();

  Relay.publish();
  ((recvAmount, pDistr) => {
    transfer(pDistr[0]).to(state.addrs[0]); // reserved for active bidder
    transfer(pDistr[1]).to(state.addrs[1]); // reserved for curator
    transfer(pDistr[2]).to(addrs[2]);
    transfer(pDistr[3]).to(addrs[3]);
    commit();

    // Step
    Relay.publish();
    transfer(pDistr[4]).to(addrs[4]);
    transfer(pDistr[5]).to(addrs[5]);
    transfer(pDistr[6]).to(addrs[6]);
    transfer(pDistr[7]).to(addrs[7]);
    commit();

    Relay.only(() => {
      const rAddr = this;
    });
    // Step
    Relay.publish(rAddr);

    transfer([
      recvAmount,
      [getUntrackedFunds(token), token],
      [getUntrackedFunds(activeToken), activeToken],
    ]).to(rAddr);
    transfer(pDistr[8]).to(addrs[8]);
    commit();
    exit();
  })(
    balance() - state.distr.sum(),
    state.distr
  );
};
// -----------------------------------------------
