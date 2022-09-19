"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Active Reverse Auction (A1)
// Version: 1.2.5 - use data for contract
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------
// TODO calculate price change per second with more precision

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

import { rStake, rUnstake } from "@KinnFoundation/stake#stake-v0.1.11r0:interface.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 8; // number of slots to distribute proceeds after sale

const FEE_MIN_ACCEPT = 9_000; // 0.009
const FEE_MIN_CONSTRUCT = 7_000; // 0.007
const FEE_MIN_RELAY = 17_000; // 0.017
const FEE_MIN_CURATOR = 10_000; // 0.1
const FEE_MIN_ACTIVE_BID = 1; // some 1
const FEE_MIN_ACTIVE_ACTIVATION = 1; // some 1


// TYPES

const MContract = Maybe(Contract);

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
  activeBidFee: UInt, // 0.001
  activeActivationFee: UInt, // 0.001
});

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
  ["activeCtc", Contract],
  ["activeBidFee", UInt],
  ["activeActivationFee", UInt],
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
  getParams: Fun([], Params),
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
      acceptFee,
      constructFee,
      relayFee,
      curatorFee,
      activeBidFee,
      activeActivationFee,
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
    activeBidFee,
    activeActivationFee
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
        activeBidFee >= FEE_MIN_ACTIVE_BID,
        "activeBidFee must be greater than or equal to minimum bid fee"
      );
      check(
        activeActivationFee >= FEE_MIN_ACTIVE_ACTIVATION,
        "activeActivationFee must be greater than or equal to minimum activation fee"
      );
    })
    .pay([
      amt + (constructFee + acceptFee + relayFee + curatorFee) + SERIAL_VER,
      [tokenAmount, token],
      [activeActivationFee, activeToken],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([amt + constructFee + SERIAL_VER, [activeActivationFee, activeToken]]).to(
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
    acceptFee,
    constructFee,
    relayFee,
    curatorFee,
    curatorAddr: Auctioneer,
    timestamp: referenceConcensusSecs,
    activeToken,
    activeAmount: 0,
    activeAddr: Auctioneer,
    activeCtc: getContract(), // ref to self never used
    activeBidFee,
    activeActivationFee,
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
      implies(!state.closed, balance() == acceptFee + relayFee + curatorFee),
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
          transfer([acceptFee + diff, [tokenAmount, token]]).to(this);
          transfer(curatorFee).to(cAddr);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              currentPrice: bal,
              who: this,
              closed: true,
              curatorAddr: cAddr,
              partTake,
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
          transfer([acceptFee + curatorFee, [tokenAmount, token]]).to(this);
          switch (mctc) {
            case Some:
              rUnstake(mctc);
            case None:
          }
          return [
            {
              ...state,
              closed: true,
              activeAmount: 0,
              activeAddr: Auctioneer,
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
        [0, [activeBidFee, activeToken]],
        (k) => {
          k(null);
          transfer([0, [activeBidFee, activeToken]]).to(addr);
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
              activeAmount: r1TokenAmount,
              activeAddr: r1Manager,
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
      check(this == state.activeAddr, "only active bidder can cancel bid");
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
              activeAmount: 0,
              activeAddr: Auctioneer,
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
