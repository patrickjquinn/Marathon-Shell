/* 
The MIT License (MIT)

Copyright (c) 2020 Anna Brondin, Marcus Nordström and Dario Salvi

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
#include "scoringStage.h"
#include "detectionStage.h"

#ifdef DUMP_FILE
#include <stdio.h>
static FILE
    *scoringFile;
static FILE *scoringFile;
#endif

static ring_buffer_t *inBuff;
static ring_buffer_t *outBuff;
static void (*nextStage)(void);

static ring_buffer_size_t windowSize = 10;
static ring_buffer_size_t midpoint = 5; //half of size

void initScoringStage(ring_buffer_t *pInBuff, ring_buffer_t *pOutBuff, void (*pNextStage)(void))
{
    inBuff = pInBuff;
    outBuff = pOutBuff;
    nextStage = pNextStage;

#ifdef DUMP_FILE
    scoringFile = fopen(DUMP_SCORING_FILE_NAME, "w+");
#endif
}

void scoringStage(void)
{
    if (ring_buffer_num_items(inBuff) == windowSize)
    {
        magnitude_t diffLeft = 0;
        magnitude_t diffRight = 0;
        data_point_t midpointData;
        ring_buffer_peek(inBuff, &midpointData, midpoint);
        data_point_t dataPoint;
        for (ring_buffer_size_t i = 0; i < midpoint; i++)
        {
            ring_buffer_peek(inBuff, &dataPoint, i);
            diffLeft += midpointData.magnitude - dataPoint.magnitude;
        }
        for (ring_buffer_size_t j = midpoint + 1; j < windowSize; j++)
        {
            ring_buffer_peek(inBuff, &dataPoint, j);
            diffRight += midpointData.magnitude - dataPoint.magnitude;
        }
        magnitude_t scorePeak = (diffLeft + diffRight) / (windowSize - 1);
        data_point_t out;
        out.time = midpointData.time;
        out.magnitude = scorePeak;
        ring_buffer_queue(outBuff, out);
        ring_buffer_dequeue(inBuff, &midpointData);
        (*nextStage)();

#ifdef DUMP_FILE
        if (scoringFile)
        {
            if (!fprintf(scoringFile, "%lld, %lld\n", out.time, out.magnitude))
                puts("error writing file");
            fflush(scoringFile);
        }
#endif
    }
}

void changeWindowSize(ring_buffer_size_t windowsize)
{
    windowSize = windowsize;
    midpoint = windowsize / 2;
}