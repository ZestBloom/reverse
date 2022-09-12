"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Active Reverse Auction (A1)
// Author: Nicholas Shellabarger
// Version: 1.2.3 - add bid fee and unlock api
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------
// TODO calculate price change per second with more precision

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 8; // number of slots to distribute proceeds after sale

const FEE_MIN_ACCEPT = 9_000; // 0.006
const FEE_MIN_CONSTRUCT = 7_000; // 0.005
const FEE_MIN_RELAY = 1_7000; // 0.017
const FEE_MIN_CURATOR = 10_000; // 0.1
const FEE_MIN_BID = 1_000; // 0.001

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

const relayInteract = {};

const Params = Object({
  tokenAmount: UInt, // NFT token amount
  startPrice: UInt, // 100
  floorPrice: UInt, // 1
  endSecs: UInt, // 1
  addrs: Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
  distr: Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  royaltyCap: UInt, // 10
  acceptFee: UInt, // 0.008
  constructFee: UInt, // 0.006
  relayFee: UInt, // 0.007
  curatorFee: UInt, // 0.1
  bidFee: UInt, // 0.001
});

const auctioneerInteract = {
  getParams: Fun([], Params),
  signal: Fun([], Null),
};

export const Event = () => [];

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  ParticipantClass("Relay", relayInteract),
];

const State = Struct([
  ["manager", Address],
  ["token", Token],
  ["tokenAmount", UInt],
  ["currentPrice", UInt],
  ["startPrice", UInt],
  ["floorPrice", UInt],
  ["closed", Bool],
  ["endSecs", UInt],
  ["priceChangePerSec", UInt],
  ["addrs", Array(Address, DIST_LENGTH)],
  ["distr", Array(UInt, DIST_LENGTH)],
  ["royaltyCap", UInt],
  ["who", Address],
  ["partTake", UInt],
  ["acceptFee", UInt],
  ["constructFee", UInt],
  ["relayFee", UInt],
  ["curatorFee", UInt],
  ["curatorAddr", Address],
  ["timestamp", UInt],
  ["activeToken", Token],
  ["activeAmount", UInt],
  ["activeAddr", Address],
]);

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
    bid: Fun([UInt], Null),
    unlock: Fun([], Null),
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
      acceptFee,
      constructFee,
      relayFee,
      curatorFee,
      bidFee,
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
    royaltyCap,
    acceptFee,
    constructFee,
    relayFee,
    curatorFee,
    bidFee
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
      check(
        acceptFee >= FEE_MIN_ACCEPT,
        "acceptFee must be greater than or equal to minimum accept fee"
      );
      check(
        constructFee >= FEE_MIN_CONSTRUCT,
        "constructFee must be greater than or equal to minimum construct fee"
      );
      check(
        relayFee >= FEE_MIN_RELAY,
        "relayFee must be greater than or equal to minimum relay fee"
      );
      check(
        curatorFee >= FEE_MIN_CURATOR,
        "curatorFee must be greater than or equal to minimum curator fee"
      );
      check(
        bidFee >= FEE_MIN_BID,
        "bidFee must be greater than or equal to minimum bid fee"
      );
    })
    .pay([
      amt + (constructFee + acceptFee + relayFee + curatorFee) + SERIAL_VER,
      [tokenAmount, token],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + constructFee + SERIAL_VER).to(addr);

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
    partTake: 0,
    acceptFee,
    constructFee,
    relayFee,
    curatorFee,
    curatorAddr: Auctioneer,
    timestamp: referenceConcensusSecs,
    activeToken,
    activeAmount: 0,
    activeAddr: Auctioneer,
  };

  v.state.set(State.fromObject(initialState));

  // Step
  const [state] = parallelReduce([initialState])
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
    .invariant(
      implies(!state.closed, balance(activeToken) == state.activeAmount),
      "active token balance accurate before closed"
    )
    .invariant(
      implies(state.closed, balance(activeToken) == 0),
      "active token balance accurate before closed"
    )
    // BALANCE
    .invariant(
      implies(!state.closed, balance() == acceptFee + relayFee + curatorFee),
      "balance accurate before close"
    )
    // REM missing invariant balance accurate after close
    .while(!state.closed)
    .paySpec([activeToken])
    // api: updates current price
    .api_(a.touch, () => {
      check(state.currentPrice >= floorPrice);
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
          ];
        },
      ];
    })
    // api: accepts offer
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
          transfer([cent, [state.activeAmount, activeToken]]).to(addr);
          transfer(sellerTake).to(Auctioneer);
          transfer([acceptFee + diff, [tokenAmount, token]]).to(this);
          transfer(curatorFee).to(cAddr);
          return [
            {
              ...state,
              currentPrice: bal,
              who: this,
              closed: true,
              curatorAddr: cAddr,
              partTake,
            },
          ];
        },
      ];
    })
    // api: bid
    .api_(a.bid, (msg) => {
      check(msg > state.activeAmount, "bid must be greater than active amount");
      return [
        [bidFee, [msg, activeToken]],
        (k) => {
          k(null);
          transfer(bidFee).to(addr);
          transfer(state.activeAmount, activeToken).to(state.activeAddr);
          return [
            {
              ...state,
              activeAmount: msg,
              activeAddr: this,
            },
          ];
        },
      ];
    })
    // api: claim
    .api_(a.unlock, () => {
      check(this == addr, "only master can unlock");
      return [
        (k) => {
          k(null);
          return [
            {
              ...state,
              activeAddr: this
            },
          ];
        }
      ];
    })
    // api: cancels auction
    .api_(a.cancel, () => {
      check(this == Auctioneer, "only auctioneer can cancel");
      return [
        (k) => {
          k(null);
          transfer([acceptFee + curatorFee, [tokenAmount, token]]).to(this);
          transfer(state.activeAmount, activeToken).to(state.activeAddr);
          return [
            {
              ...state,
              closed: true,
            },
          ];
        },
      ];
    })
    .timeout(false);
  commit();

  Relay.publish();
  // Step
  ((recvAmount, pDistr) => {
    transfer(pDistr[0]).to(state.activeAddr); // reserved
    transfer(pDistr[1]).to(addrs[1]);
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
    transfer(recvAmount).to(rAddr);
    commit();
    exit();
  })(
    balance() - distrTake * state.partTake,
    distr.map((d) => d * state.partTake)
  );
};
// -----------------------------------------------
