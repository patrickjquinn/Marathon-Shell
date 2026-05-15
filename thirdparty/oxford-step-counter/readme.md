# C-step-counter

This is the port of the step counting algorithm for C.
It was developed within the thesis *Open-source algorithm for wearables in healthcare-applications* made by Anna Brondin & Marcus Nordstrom at Malmö University.

## Guide

This implementation does no assume to be run in a mobile phone and is suitable for embedded devices like smartwatches.
The input is assumed to be the raw values from the acceerometer. This also means that some configuration is needed depending on the actual accelerometry and environment.

Most configurable parameters are in include/config.h.

1. you can choose to use an approximated implementation of the square root in case your CPU doesn't have floating point unit. Include `sqrt.h` in this case.

2. define the datatypes used throughout the code. These depend on the resolution of your acceleration samples:
  - `accel_t` is the type that stores acceleration samples (for example int16_t)
  - `magnitude_t` stores the magnitude of acceleration, this must be 1 bit bigger than the resolution of your acceleration samples
  - `accumulator_t` accumulates samples when computing linear filters. Its size depends on the size of the filter
  - `steps_t` stores the number of steps measured since the algorithm was started, keep it big or restart the algorithm when this is about to overflow
  - `time_t` this stores the time, preferably in ms, since the start of the algorithm. The algorithm is not wobust to this variable rolling over

3. define the threshold used for detecting motion, `MOTION_THRESHOLD`, this is the difference between min and max acceleration above which the algorithm will try to detect steps. Tt is used to filter out signals when there is no motion.

4. decide if you want to skip interpolation with `SKIP_INTERPOLATION` and the filtering step with `SKIP_FILTER`.

5. for testing, you can dump the output of all stages on files using the defines `DUMP_MAGNITUDE_FILE_NAME`, `DUMP_INTERPOLATED_FILE_NAME`, `DUMP_FILTERED_FILE_NAME`, `DUMP_SCORING_FILE_NAME`, `DUMP_DETECTION_FILE_NAME`, `DUMP_POSTPROC_FILE_NAME`.

After these, you need to configure:

* The constant timeScalingFactor in preProcessingStage.c is used to scale the timestamps if they are not in ms.
* The constant timeScalingFactor in preProcessingStage.c is used to scale the timestamps if they are not in ms.
* The coefficients of filterStage.c (`magnitude_t filter_taps[FILTER_TAP_NUM]`) depend on the sampling frequency and what frequencies you want to cut out from the signal. They are used in a FIR low pass filter to remove frequencies above those possible with human walk (for example above 3Hz. You can use [this online tool](http://t-filter.engineerjs.com/) to compute different coefficients.
* There are 3 constants that need to be optimised in the algorithm: the window size, the detection threshold and the minimum inter-step time threshold. These constants depend on your actual accelerometry and environment so they need to be optimised experimentally. This is the suggested procedure:
   1. Walk 150 steps (count them manually) while collecting raw accelerometry data into a CSV file formated as *time(ms), X, Y, Z*
   2. These raw data should be collected multiple times and in different conditions (e.g. different walking speeds, styles, different terrains etc.)
   3. Perform a grid-search of the best parameters by comparing the counted steps with the "ground truth", 150. The combination that minimises the error wins. [This repository](https://github.com/MarcusNordstrom/C-optimize-variables) can be used for the procedure.
   Find the best constants with [C-optimize-variables]
   4. Modify the constants in this algorithm, for that, you can use the functions: `changeWindowSize()`, `changeDetectionThreshold()` and `changeTimeThreshold()`

## Contributing

Contributins are very welcome!

## License

MIT, see License file.