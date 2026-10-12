.pragma library

function app(id, name, extra) {
    return Object.assign({
        "app_id": id,
        "name": name,
        "summary": name + " for your phone",
        "developer_name": name + " Developers",
        "arches": ["aarch64"]
    }, extra || {});
}

function collections() {
    return {
        "verified": [app("org.example.Hero", "Hero")],
        "trending": [app("org.example.Hero", "Hero"), app("org.example.T1", "Trend One"), app("org.example.T2", "Trend Two"), app("org.example.T3", "Trend Three"), app("org.example.T4", "Trend Four")],
        "mobile": [app("org.example.M1", "Mobile One"), app("org.example.T1", "Trend One"), app("org.example.M2", "Mobile Two")],
        "recently-added": [app("org.example.N1", "New One")],
        "popular": [app("org.example.P1", "Popular One"), app("org.example.P2", "Popular Two")]
    };
}

function fullApp(id) {
    return {
        "id": id,
        "name": "Maps",
        "summary": "Find places around the world",
        "description": "<p>Maps gives you quick access to maps all across the world.</p>",
        "developer_name": "The GNOME Project",
        "project_license": "GPL-2.0+",
        "categories": ["Utility"],
        "isMobileFriendly": false,
        "metadata": { "flathub::verification::verified": "true" },
        "urls": { "homepage": "https://apps.gnome.org/Maps/" },
        "releases": [{ "version": "46.1", "timestamp": "1700000000", "description": "<p>Bug fixes</p>" }],
        "screenshots": [
            { "caption": "Search", "sizes": [{ "src": "https://dl.flathub.org/a.png", "width": "1080", "height": "1920" }] },
            { "sizes": [{ "src": "https://dl.flathub.org/b.png", "width": "1080", "height": "1920" }] }
        ]
    };
}

function summary() {
    return {
        "download_size": 5242880,
        "installed_size": 20971520,
        "installs_last_month": 12345,
        "metadata": { "permissions": { "shared": ["network"], "filesystems": ["home"], "sockets": ["wayland", "pulseaudio"] } }
    };
}
