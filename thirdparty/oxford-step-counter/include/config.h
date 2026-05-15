#include <inttypes.h>

// choose osc_sqrt instead of math for a non-float dependent implementation
#include "osc_sqrt.h"
// #include <math.h>

// type for the accelerometer samples, this depends on your hardware
// for example, if your accelerometer uses 12bits then an int16_t would suffice
typedef int16_t accel_t;

// type used for time: warning the algorithm is not robust to roll-over of this variable
// reset the algorithm if time overflows
// preferably, time should be in ms, if not, use timeScalingFactor in the preprocessing stage to adjust it to ms
// example: a year worth of ms needs 35 bits, 32 bits allows you to store about 50 days of ms
// as time doesn't go back, using unsigned integers makes sense
typedef int32_t osc_time_t;

// magnitude of acceleration
// this should be 1 bit bigger than accel_t
// example: if the accelerometer works at 12 bits, magnitude should be 13 bits, therefore choosing int16_t for both will do
typedef uint16_t magnitude_t;

// accumulator of magnitude, should be bigger than magnitude
// the size depends on the length of the filter in the filtering stage
// example: accelerometer works at 12 bits, the filter has 8 taps -> accumulator should be at least 12 + 3 bits -> using int16_t will do
typedef int32_t accumulator_t;

// steps count type
// the size of this depends on what is the maximum number of steps you are willing to show and store
// example: is the step count is reset every 24h and one walks no more than 20k / day (reasonable) -> 16 bits should be enough
typedef uint16_t steps_t;

// difference between min and max acceleration to detect motion
#define MOTION_THRESHOLD 500

// skip interpolation
#define SKIP_INTERPOLATION

// skip filtering step
#define SKIP_FILTER

// use this to allow dumping each stage on file, useful for debugging
// #define DUMP_FILE
#define DUMP_MAGNITUDE_FILE_NAME    "magnitude.csv"
#define DUMP_INTERPOLATED_FILE_NAME "interpolated.csv"
#define DUMP_FILTERED_FILE_NAME     "filtered.csv"
#define DUMP_SCORING_FILE_NAME      "scoring.csv"
#define DUMP_DETECTION_FILE_NAME    "detection.csv"
#define DUMP_POSTPROC_FILE_NAME     "postproc.csv"