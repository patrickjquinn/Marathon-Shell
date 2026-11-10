/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/

.pragma library
.import Sailfish.Silica.private 1.0 as SilicaPrivate

function _isLeapYear(year) {
    return ((year % 4 == 0) && (year % 100 != 0))
            || (year % 400 == 0)
}

function _maxDaysForMonth(month, year) {
    switch (month) {
    case 2:
        return _isLeapYear(year) ? 29 : 28
    case 4:
    case 6:
    case 9:
    case 11:
        return 30
    default:
        return 31
    }
}

// Returns the day (1-31) that is the first day of the week when displaying
// the given month. Given month should be 1-12.
// i.e. the returned date is in either this month or the last week of the
// previous month
// weekstart indicates on which day a week starts, sunday=0, monday=1
function _getStartDateForMonthView(year, month, weekstart) {
    var start = new Date(year, month-1, 1, 12)
    if (start.getDay() > 0) {
        start.setDate(start.getDate() - start.getDay())
    }
    start.setDate(start.getDate() + weekstart)
    if (start.getDate() > 1 && start.getMonth()+1 === month) {
        // shifting forward to week start skipped over the 1st of this month, go back a week
        // to the last week day of previous month
        start.setDate(start.getDate() - 7)
    }
    return start
}

// Returns an array of week numbers for the given month. The weekCount is the
// number of weeks to put in the returned array; e.g. if month=1 and
// weekCount=6 this returns [1,2,3,4,5,6] or possibly [52,1,2,3,4,5] if Jan 1st
// falls after Thursday for this year.
// Given month should be 1-12.
function _loadWeekNumbers(model, year, month, day, weekCount) {
    var numbers = SilicaPrivate.Util.weekNumberList(year, month, day, weekCount)
    for (var i = 0; i < numbers.length; ++i) {
        if (model.count <= i) {
            model.append({'weekNumber': numbers[i]})
        } else {
            model.setProperty(i, 'weekNumber', numbers[i])
        }
    }
}
