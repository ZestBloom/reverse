"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Active Reverse Auction (A1)
// Version: 1.2.4 - use stake
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------
// TODO calculate price change per second with more precision

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

import { rStake, rUnstake } from "@KinnFoundation/stake#stake-v0.1.11r0:interface.rsh";

import { Params } from "@KinnFoundation/reverse#reverse-v0.1.11r0:interface.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 9; // number of slots to distribute proceeds after sale

const FEE_MIN_ACCEPT = 9_000; // 0.009
const FEE_MIN_CONSTRUCT = 7_000; // 0.007
const FEE_MIN_RELAY = 17_000; // 0.017
const FEE_MIN_CURATOR = 10_000; // 0.1
const FEE_MIN_BID = 10_000; // 0.001
const FEE_MIN_ACTIVE_BID = 1; // some 1

const ADDR_RESERVED_ACTIVE_BIDDER = 0;
const ADDR_RESERVED_CURATOR = 1;

// TYPES

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
  //["acceptFee", UInt],
  //["constructFee", UInt],
  //["relayFee", UInt],
  //["curatorFee", UInt],
  //["curatorAddr", Address],
  ["timestamp", UInt],
  ["activeToken", Token],
  ["activeAmount", UInt],
  //["activeAddr", Address],
  ["activeCtc", Contract],
  //["activeBidFee", UInt],
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
    buy: Fun([Address], Null),
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
      //acceptFee,
      //constructFee,
      //relayFee,
      //curatorFee,
      //bidFee,
      //activeBidFee,
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
    //acceptFee,
    //constructFee,
    //relayFee,
    //curatorFee,
    //bidFee,
    //activeBidFee
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
      /*
      check(
        acceptFee >= FEE_MIN_ACCEPT,
        "acceptFee must be greater than or equal to minimum accept fee"
      );
      */
      /*
      check(
        constructFee >= FEE_MIN_CONSTRUCT,
        "constructFee must be greater than or equal to minimum construct fee"
      );
      */
      /*
      check(
        relayFee >= FEE_MIN_RELAY,
        "relayFee must be greater than or equal to minimum relay fee"
      );
      */
      /*
      check(
        curatorFee >= FEE_MIN_CURATOR,
        "curatorFee must be greater than or equal to minimum curator fee"
      );
      */
      /*
      check(
        bidFee >= FEE_MIN_BID,
        "bidFee must be greater than or equal to minimum bid fee"
      );
      */
      /*
      check(
        activeBidFee >= FEE_MIN_ACTIVE_BID,
        "activeBidFee must be greater than or equal to minimum bid fee"
      );
      */
    })
    .pay([
      amt +
        /*constructFee +*/ /*acceptFee +*/ /*relayFee*/ /*+ curatorFee*/ 0 +
        SERIAL_VER,
      [tokenAmount, token],
      [1_000_000, activeToken],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([amt + /*constructFee +*/ SERIAL_VER, [1_000_000, activeToken]]).to(
    addr
  );

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
    //acceptFee,
    //constructFee,
    //relayFee,
    //curatorFee,
    //curatorAddr: Auctioneer,
    timestamp: referenceConcensusSecs,
    activeToken,
    activeAmount: 0,
    //activeAddr: Auctioneer,
    activeCtc: getContract(),
    //activeBidFee,
  };

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
    .invariant(balance(activeToken) == 0, "active token balance accurate")
    // BALANCE
    .invariant(
      implies(
        !state.closed,
        balance() == /*acceptFee +*/ /*relayFee*/ /*+ curatorFee*/ 0
      ),
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
          ];
        },
      ];
    })
    .api_(a.buy, (cAddr) => {
      return [
        [state.currentPrice, [0, activeToken]],
        (k) => {
          k(null);
          const bal = state.currentPrice;
          const cent = bal / 100;
          const remaining = bal - cent;
          const partTake = remaining / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = remaining - proceedTake;
          transfer(cent).to(addr);
          transfer(sellerTake).to(Auctioneer);
          transfer([/*acceptFee,*/ [tokenAmount, token]]).to(this);
          if (getContract() != state.activeCtc) {
            rUnstake(state.activeCtc);
          }
          return [
            {
              ...state,
              partTake,
              closed: true,
              addrs: Array.set(state.addrs, ADDR_RESERVED_CURATOR, cAddr),
            },
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
          transfer([/*acceptFee +*/ diff, [tokenAmount, token]]).to(this);
          //transfer(curatorFee).to(cAddr);
          if (getContract() != state.activeCtc) {
            rUnstake(state.activeCtc);
          }
          return [
            {
              ...state,
              currentPrice: bal,
              who: this,
              closed: true,
              addrs: Array.set(state.addrs, ADDR_RESERVED_CURATOR, cAddr),
              partTake,
            },
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
          transfer([
            /*acceptFee*/ /*+ curatorFee*/ /*,*/ [tokenAmount, token],
          ]).to(this);
          if (getContract() != state.activeCtc) {
            rUnstake(state.activeCtc);
          }
          return [
            {
              ...state,
              closed: true,
              activeAmount: 0,
              addrs: Array.set(state.addrs, ADDR_RESERVED_ACTIVE_BIDDER, this),
              activeCtc: getContract(),
            },
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
        [/*bidFee, */ 0, [1, activeToken]],
        (k) => {
          k(null);
          transfer([/*bidFee, */ 0, [1, activeToken]]).to(addr);
          const { manager: r1Manager, tokenAmount: r1TokenAmount } = rStake(
            ctc,
            activeToken,
            state.activeAmount
          );
          if (getContract() != state.activeCtc) {
            rUnstake(state.activeCtc);
          }
          return [
            {
              ...state,
              addrs: Array.set(
                state.addrs,
                ADDR_RESERVED_ACTIVE_BIDDER,
                r1Manager
              ),
              activeAmount: r1TokenAmount,
              activeCtc: ctc,
            },
          ];
        },
      ];
    })
    // api: bid cancel
    // allows the bidder to cancel their bid
    // unstakes active token if any
    .api_(a.bidCancel, () => {
      check(this == addrs[ADDR_RESERVED_ACTIVE_BIDDER], "only active bidder can cancel bid");
      return [
        (k) => {
          k(null);
          if (getContract() != state.activeCtc) {
            rUnstake(state.activeCtc);
          }
          return [
            {
              ...state,
              activeAmount: 0,
              addrs: Array.set(state.addrs, ADDR_RESERVED_ACTIVE_BIDDER, Auctioneer),
              activeCtc: getContract(),
            },
          ];
        },
      ];
    })
    .timeout(false);
  commit();

  // Step
  Relay.publish();
  ((recvAmount, pDistr) => {
    transfer(pDistr[0]).to(state.addrs[0]); // immutable reserved for active bidder
    transfer(pDistr[1]).to(state.addrs[1]); // immutable reserved for curator
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
    transfer(pDistr[8]).to(addrs[8]);
    commit();
    exit();
  })(
    balance() - distrTake * state.partTake,
    distr.map((d) => d * state.partTake)
  );
};
// -----------------------------------------------
