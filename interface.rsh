"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Active Reverse Auction (A1)
// Version: 1.2.8 - updat stake add delegate
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------
// TODO calculate price change per second with more precision

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

import {
  view,
  baseEvents,
  baseState
} from "@KinnFoundation/base#base-v0.1.11r4:interface.rsh";

import {
  rStake,
  rUnstake
} from "@KinnFoundation/stake#stake-v0.1.11r1:interface.rsh";

import {
  Params,
  State as ReverseState,
  MContract
} from "@KinnFoundation/reverse#reverse-v0.1.11r3:interface.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 10; // number of slots to distribute proceeds after sale

const FEE_MIN_ACTIVE_BID = 1; // 1au
const FEE_MIN_ACTIVE_ACTIVATION = 1; // 1au

/*
 * namedd indices for addrs
 */
const ADDR_RESERVED_ACTIVE_BIDDER = 0;
const ADDR_RESERVED_CURATOR = 1;
const ADDR_RESERVED_ADDR = 2;

// TYPES

const ActiveState = Struct([
  ["activeToken", Token],
  ["activeAmount", UInt],
  ["activeCtc", Contract],
]);

const State = Struct([
  ...Struct.fields(ReverseState(DIST_LENGTH)),
  ...Struct.fields(ActiveState),
]);

// FUN

const fState = (State) => Fun([], State);
export const fTouch = Fun([], Null);
export const fAcceptOffer = Fun([Address], Null);
export const fCancel = Fun([], Null);
export const fBid = Fun([Contract], Null);
export const fBidCancel = Fun([], Null);

// REMOTE FUN

export const rState = (ctc, State) => {
  const r = remote(ctc, { state: fState(State) });
  return r.state();
};

export const rTouch = (ctc) => {
  const r = remote(ctc, { touch: fTouch });
  r.touch();
};

export const rBid = (ctc) => {
  const r = remote(ctc, { bid: fBid });
  r.bid();
};

// API

export const api = {
  touch: fTouch,
  acceptOffer: fAcceptOffer,
  cancel: fCancel,
  bid: fBid,
  bidCancel: fBidCancel,
};

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
};

const relayInteract = {};

const eveInteract = {};

// CONTRACT

export const Event = () => [Events({ ...baseEvents })];

export const Participants = () => [
  Participant("Manager", auctioneerInteract),
  Participant("Relay", relayInteract),
  Participant("Eve", eveInteract),
];

export const Views = () => [View(view(State))];

export const Api = () => [API(api)];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token, tok1: activeToken },
    [addr, _],
    [Manager, Relay, _],
    [v],
    [a],
    [e],
  ] = map;
  Manager.only(() => {
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
  Manager.publish(
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
      amt + SERIAL_VER,
      [tokenAmount, token],
      [FEE_MIN_ACTIVE_ACTIVATION, activeToken],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([amt + SERIAL_VER, [FEE_MIN_ACTIVE_ACTIVATION, activeToken]]).to(
    addr
  );

  e.appLaunch();

  const distrTake = distr.sum();

  const referenceConcensusSecs = thisConsensusSecs();

  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;

  const initialState = {
    ...baseState(Manager),
    token,
    tokenAmount,
    currentPrice: startPrice,
    startPrice,
    floorPrice,
    endSecs,
    priceChangePerSec: dk / precision,
    addrs: Array.set(addrs, ADDR_RESERVED_ADDR, addr),
    distr,
    royaltyCap: royaltyCap,
    who: Manager,
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
      implies(!state.closed, balance() == 0),
      "balance accurate before close"
    )
    .invariant(
      implies(
        state.closed,
        balance() == state.distr.slice(2, DIST_LENGTH - 2).sum()
      ),
      "balance accurate after close"
    )
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
      check(
        state.addrs[ADDR_RESERVED_ACTIVE_BIDDER] != this,
        "cannot accept offer as bidder"
      );
      check(Manager != this, "cannot accept offer as manager");
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
          const partTake = bal / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = bal - proceedTake;
          transfer(distr[0] * partTake).to(
            state.addrs[ADDR_RESERVED_ACTIVE_BIDDER]
          );
          transfer(distr[1] * partTake).to(state.addrs[ADDR_RESERVED_CURATOR]);
          transfer(sellerTake).to(Manager);
          transfer([diff, [tokenAmount, token]]).to(this);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              addrs: Array.set(state.addrs, ADDR_RESERVED_CURATOR, cAddr),
              distr: Array.set(
                Array.set(
                  distr.map((d) => d * partTake),
                  ADDR_RESERVED_ACTIVE_BIDDER,
                  0
                ),
                ADDR_RESERVED_CURATOR,
                0
              ),
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
      check(this == Manager, "only auctioneer can cancel");
      return [
        (k) => {
          k(null);
          transfer([[tokenAmount, token]]).to(this);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              distr: Array.replicate(DIST_LENGTH, 0),
              closed: true,
              currentPrice: 0,
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
      check(
        this == state.addrs[ADDR_RESERVED_ACTIVE_BIDDER],
        "only active bidder can cancel bid"
      );
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
                Manager
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
  e.appClose();
  commit();

  // Step
  Relay.publish();
  if (
    state.who == Manager ||
    state.distr.slice(2, DIST_LENGTH - 2).sum() == 0
  ) {
    transfer(state.distr.slice(2, DIST_LENGTH - 2).sum()).to(Manager);
    commit();
    exit();
  }
  transfer(state.distr[2]).to(addrs[2]);
  transfer(state.distr[3]).to(addrs[3]);
  transfer(state.distr[4]).to(addrs[4]);
  transfer(state.distr[5]).to(addrs[5]);
  commit();
  // Step
  Anybody.publish();
  if (state.distr.slice(6, DIST_LENGTH - 6).sum() != 0) {
    transfer(state.distr[6]).to(addrs[6]);
    transfer(state.distr[7]).to(addrs[7]);
    transfer(state.distr[8]).to(addrs[8]);
    transfer(state.distr[9]).to(addrs[9]);
  }
  commit();
  exit();
};
// -----------------------------------------------
