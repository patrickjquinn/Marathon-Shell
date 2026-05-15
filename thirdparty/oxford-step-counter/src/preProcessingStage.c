/* 
The MIT License (MIT)

Copyright (c) 2020 Anna Brondin and Marcus Nordström

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
#include "preProcessingStage.h"
#include "config.h"

#ifdef DUMP_FILE
#include <stdio.h>
static FILE
    *magnitudeFile;
static FILE *interpolatedFile;
#endif

static ring_buffer_t *inBuff;
static ring_buffer_t *outBuff;
static void (*nextStage)(void);
static uint8_t samplingPeriod = 80;    //in ms, this can be smaller than the actual sampling frequency, but it will result in more computations
static uint16_t timeScalingFactor = 1; //use this for adjusting time to ms, in case the clock has higher precision
static osc_time_t lastSampleTime = -1;

void initPreProcessStage(ring_buffer_t *pInBuff, ring_buffer_t *pOutBuff, void (*pNextStage)(void))
{
    inBuff = pInBuff;
    outBuff = pOutBuff;
    nextStage = pNextStage;

#ifdef DUMP_FILE
    magnitudeFile = fopen(DUMP_MAGNITUDE_FILE_NAME, "w+");
    interpolatedFile = fopen(DUMP_INTERPOLATED_FILE_NAME, "w+");
#endif
}

static data_point_t linearInterpolate(data_point_t dp1, data_point_t dp2, int64_t interpTime)
{
    magnitude_t mag = (dp1.magnitude + ((dp2.magnitude - dp1.magnitude) / (dp2.time - dp1.time)) * (interpTime - dp1.time));
    data_point_t interp;
    interp.time = interpTime;
    interp.magnitude = mag;
    return interp;
}

static void outPutDataPoint(data_point_t dp)
{
    lastSampleTime = dp.time;
    ring_buffer_queue(outBuff, dp);
    (*nextStage)();

#ifdef DUMP_FILE
    if (interpolatedFile)
    {
        if (!fprintf(interpolatedFile, "%lld, %lld\n", dp.time, dp.magnitude))
            puts("error writing file");
        fflush(interpolatedFile);
    }
#endif
}

void preProcessSample(osc_time_t time, accel_t x, accel_t y, accel_t z)
{
    time = time / timeScalingFactor;

    magnitude_t magnitude = (magnitude_t)osc_sqrt((accumulator_t)(x * x + y * y + z * z));
    data_point_t dataPoint;
    dataPoint.time = time;
    dataPoint.magnitude = magnitude;

#ifdef DUMP_FILE
    if (magnitudeFile)
    {
        if (!fprintf(magnitudeFile, "%lld, %lld\n", dataPoint.time, dataPoint.magnitude))
            puts("error writing file");
    }
#endif

#ifdef SKIP_INTERPOLATION
    outPutDataPoint(dataPoint);
#else
    ring_buffer_queue(inBuff, dataPoint);
    if (ring_buffer_num_items(inBuff) >= 2)
    {
        data_point_t dp1;
        data_point_t dp2;
        // take last 2 elements
        ring_buffer_peek(inBuff, &dp1, 0);
        ring_buffer_peek(inBuff, &dp2, 1);
        if (lastSampleTime == -1)
            lastSampleTime = dp1.time;

        if (dp2.time - lastSampleTime == samplingPeriod)
        {
            // no need to interpolate!
            outPutDataPoint(dp2);
        }
        else if (dp2.time - lastSampleTime > samplingPeriod)
        {
            int8_t numberOfPoints = 1 + ((((dp2.time - lastSampleTime)) - 1) / samplingPeriod); //number of points to be generated, ceiled

            for (int8_t i = 1; i < numberOfPoints; i++)
            {
                osc_time_t interpTime = lastSampleTime + samplingPeriod;

                if (dp1.time <= interpTime && interpTime <= dp2.time)
                {
                    data_point_t interpolated = linearInterpolate(dp1, dp2, interpTime);
                    outPutDataPoint(interpolated);
                }
            }
        }
        // remove oldest element in queue
        data_point_t dataPoint;
        ring_buffer_dequeue(inBuff, &dataPoint);
    }
#endif
}

void resetPreProcess(void)
{
    lastSampleTime = -1;

#ifdef DUMP_FILE
    if (magnitudeFile)
    {
        fflush(magnitudeFile);
    }
    if (interpolatedFile)
    {
        fflush(interpolatedFile);
    }
#endif
}