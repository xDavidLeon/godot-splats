/* Coordinates along a closed carrier, independent of how its seam is placed. */
(function (K) {
  const P = K.procedural || K.authoring;

  function wrap(value, period = 1) {
    const remainder = value % period;
    return remainder < 0 ? (remainder + period) % period : remainder === 0 ? 0 : remainder;
  }

  function delta(value, origin, period = 1) {
    let distance = value - origin;
    if (Math.abs(distance) >= period) distance = wrap(value, period) - wrap(origin, period);
    if (distance >= period / 2) return distance - period;
    if (distance < -period / 2) return distance + period;
    return distance;
  }

  function unwrap(values, period = 1) {
    const positions = Array.from(values, value => wrap(value, period));
    if (positions.length < 2) return positions;
    const sorted = positions.slice().sort((a, b) => a - b);
    let start = sorted[0], largest = period - sorted.at(-1) + start;
    for (let i = 1; i < sorted.length; i++) {
      const gap = sorted[i] - sorted[i - 1];
      if (gap > largest) {
        largest = gap;
        start = sorted[i];
      }
    }
    return positions.map(position => position < start ? position + period : position);
  }

  P.periodicCoordinates = { wrap, delta, unwrap };
})(KIT);
