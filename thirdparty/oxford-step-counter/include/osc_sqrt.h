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
#ifndef STEP_COUNTING_ALGO_UTILS_H
#define STEP_COUNTING_ALGO_UTILS_H
#include <stdint.h>

static int64_t osc_sqrt(int64_t number) {
    int64_t base, i, y;
    base = 67108864; //2^24
    y    = 0;
    for (i = 1; i <= 24; i++) {
        y += base;
        if ((y * y) > number) {
            y -= base; // base should not have been added, so we substract again
        }
        base = base >> 1; // shift 1 digit to the right = divide by 2
    }
    return y;
}

/*static long isqrt(long number)
{ //http://www.codecodex.com/wiki/Calculate_an_integer_square_root#C
  unsigned long n = 1;
  unsigned long n1 = ((n + (number / n)) >> 1);

  while (n1 - n > 1)
  {
    n = n1;
    n1 = ((n + (number / n)) >> 1);
  }
  while (n1 * n1 > number)
    n1--;
  return (long)n1;
}*/
#endif