import QtQuick
import QtTest
import "../GalleryModel.js" as Model

TestCase {
    name: "GalleryModel"

    readonly property var now: new Date(2026, 9, 12, 12, 0)

    function photo(id, album, date) {
        return { id: id, path: "file:///p/" + album + "/IMG%20" + id + ".jpg", album: album, timestamp: date.getTime() };
    }

    function video(id, date) {
        return { id: id, path: "file:///p/VID_" + id + ".mp4", thumbnailPath: "", timestamp: date.getTime() };
    }

    function test_fileNameDecodes() {
        compare(Model.fileName(photo(3, "Trip", now)), "IMG 3.jpg");
        compare(Model.fileName(null), "");
    }

    function test_filterByNameAlbumAndDate() {
        const ps = [photo(1, "Trip", now), photo(2, "Camera Roll", new Date(2025, 0, 5))];
        compare(Model.filter(ps, "").length, 2);
        compare(Model.filter(ps, "  trip ").map(p => p.id), [1]);
        compare(Model.filter(ps, "img 2").map(p => p.id), [2]);
        compare(Model.filter(ps, "january 2025").map(p => p.id), [2]);
        compare(Model.filter(ps, "nothing").length, 0);
    }

    function test_albumPhotos() {
        const ps = [photo(1, "A", now), photo(2, "B", now), photo(3, "A", now)];
        compare(Model.albumPhotos(ps, "A").map(p => p.id), [1, 3]);
    }

    function test_memoriesClusterByYearWithinThreeDays() {
        const ps = [
            photo(1, "A", new Date(2025, 9, 10)),
            photo(2, "A", new Date(2024, 9, 14)),
            photo(3, "A", new Date(2025, 9, 1)),
            photo(4, "A", new Date(2026, 9, 12)),
            photo(5, "A", new Date(2025, 9, 15))
        ];
        const videos = [{ id: 9, path: "file:///v.mp4", timestamp: new Date(2024, 9, 12).getTime() }];
        const m = Model.memoryClusters(ps, videos, now);
        compare(m.length, 2);
        compare(m[0].years, 1);
        compare(m[0].photos.map(p => p.id), [1, 5]);
        compare(m[0].videoCount, 0);
        compare(m[1].years, 2);
        compare(m[1].photos.map(p => p.id), [2]);
        compare(m[1].videoCount, 1);
        compare(Model.memoryPhotos(m, 2).map(p => p.id), [2]);
        compare(Model.memoryPhotos(m, 7), []);
    }

    function test_collectionsOrderAndCovers() {
        const ps = [photo(1, "B", new Date(2025, 9, 12)), photo(2, "A", now)];
        const albums = [{ id: "A", name: "A", photoCount: 1 }, { id: "B", name: "B", photoCount: 1 }];
        const rows = Model.collections(ps, [], albums, Model.memoryClusters(ps, [], now));
        compare(rows.map(r => r.kind), ["all", "memory", "album", "album"]);
        compare(rows[0].count, 2);
        compare(rows[0].cover.id, 1);
        compare(rows[1].years, 1);
        compare(rows[2].cover.id, 2);
        compare(rows[3].cover.id, 1);
        compare(rows.map(r => r.section), ["", "memories", "albums", "albums"]);
    }

    function test_noCollectionsWithoutPhotos() {
        compare(Model.collections([], [], [{ id: "A", name: "A", photoCount: 0 }], []), []);
    }

    function test_videosGetARowAndCountInAll() {
        const ps = [photo(1, "A", now)];
        const vs = [video(5, now), video(6, now)];
        const rows = Model.collections(ps, vs, [], []);
        compare(rows.map(r => r.kind), ["all", "videos"]);
        compare(rows[0].count, 1);
        compare(rows[0].videoCount, 2);
        compare(rows[0].cover.id, 1);
        compare(rows[1].count, 0);
        compare(rows[1].videoCount, 2);
        compare(rows[1].cover, null);
        compare(Model.collections([], vs, [], []).map(r => r.kind), ["all", "videos"]);
    }

    function test_countText() {
        compare(Model.countText(0, 0), "0 photos");
        compare(Model.countText(1, 0), "1 photo");
        compare(Model.countText(0, 2), "2 videos");
        compare(Model.countText(3, 1), "3 photos · 1 video");
    }

    function test_mergedIsNewestFirst() {
        const ps = [photo(1, "A", new Date(2026, 0, 3)), photo(2, "A", new Date(2026, 0, 1))];
        const vs = [video(5, new Date(2026, 0, 2))];
        compare(Model.merged(ps, vs).map(m => m.id), [1, 5, 2]);
        verify(Model.isVideo(vs[0]));
        verify(!Model.isVideo(ps[0]));
    }

    function test_pickRandomAvoidsCurrent() {
        const ps = [photo(1, "A", now), photo(2, "A", now)];
        compare(Model.pickRandom([], null, 0.5), null);
        compare(Model.pickRandom(ps, ps[0], 0.0).id, 2);
        compare(Model.pickRandom(ps, ps[1], 0.99).id, 1);
        compare(Model.pickRandom([ps[0]], ps[0], 0.5).id, 1);
        compare(Model.pickRandom(ps, null, 0.99).id, 2);
    }

    function test_withoutId() {
        compare(Model.withoutId([photo(1, "A", now), photo(2, "A", now)], 1).map(p => p.id), [2]);
    }
}
