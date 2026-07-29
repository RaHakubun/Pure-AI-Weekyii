(() => {
    const slides = [...document.querySelectorAll(".slide")];
    const dotHost = document.querySelector(".nav-dots");
    const progress = document.querySelector(".progress");
    const previous = document.querySelector("[data-previous]");
    const next = document.querySelector("[data-next]");
    const languageLink = document.querySelector("[data-language-link]");
    const appearance = document.querySelector("[data-appearance]");
    const themeColor = document.querySelector('meta[name="theme-color"]');
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const systemAppearance = window.matchMedia("(prefers-color-scheme: light)");
    const appearanceKey = "weekyii-appearance";
    let current = 0;
    let wheelLocked = false;
    let touchStartY = null;

    if (!slides.length) return;

    function resolveAppearance(mode) {
        return mode === "system" ? (systemAppearance.matches ? "light" : "dark") : mode;
    }

    function applyAppearance(mode, persist = false) {
        const safeMode = ["system", "light", "dark"].includes(mode) ? mode : "system";
        const resolved = resolveAppearance(safeMode);
        document.documentElement.dataset.themeMode = safeMode;
        document.documentElement.dataset.theme = resolved;
        if (appearance) appearance.value = safeMode;
        if (themeColor) themeColor.content = resolved === "light" ? "#efe3ca" : "#080705";
        if (persist) localStorage.setItem(appearanceKey, safeMode);
    }

    applyAppearance(document.documentElement.dataset.themeMode || "system");
    appearance?.addEventListener("change", event => {
        applyAppearance(event.target.value, true);
    });
    systemAppearance.addEventListener("change", () => {
        if (document.documentElement.dataset.themeMode === "system") applyAppearance("system");
    });

    slides.forEach((slide, index) => {
        const dot = document.createElement("button");
        dot.type = "button";
        dot.className = "nav-dot";
        dot.dataset.label = slide.dataset.nav || `${index + 1}`;
        dot.setAttribute("aria-label", slide.dataset.nav || `Chapter ${index + 1}`);
        dot.addEventListener("click", () => show(index));
        dotHost.append(dot);
    });

    const dots = [...dotHost.children];

    function bounded(index) {
        return Math.max(0, Math.min(slides.length - 1, index));
    }

    function show(index, updateHash = true) {
        current = bounded(index);
        slides.forEach((slide, slideIndex) => {
            const active = slideIndex === current;
            slide.classList.toggle("active", active);
            slide.classList.toggle("before", slideIndex < current);
            slide.setAttribute("aria-hidden", active ? "false" : "true");
            slide.inert = !active;
            if (active) slide.querySelector(".slide-inner")?.scrollTo(0, 0);
        });
        dots.forEach((dot, dotIndex) => {
            const active = dotIndex === current;
            dot.classList.toggle("active", active);
            dot.setAttribute("aria-current", active ? "step" : "false");
        });
        previous.disabled = current === 0;
        next.disabled = current === slides.length - 1;
        progress.style.transform = `scaleX(${(current + 1) / slides.length})`;
        document.title = `${slides[current].dataset.nav} — Weekyii`;
        if (languageLink) {
            const target = new URL(languageLink.href, window.location.href);
            target.hash = `chapter-${current + 1}`;
            languageLink.href = target.toString();
        }
        if (updateHash) {
            history.replaceState(null, "", `#chapter-${current + 1}`);
        }
    }

    function step(amount) {
        const target = bounded(current + amount);
        if (target !== current) show(target);
    }

    function activeContentCanScroll(direction) {
        const content = slides[current].querySelector(".slide-inner");
        if (!content || content.scrollHeight <= content.clientHeight + 2) return false;
        if (direction > 0) return content.scrollTop + content.clientHeight < content.scrollHeight - 2;
        return content.scrollTop > 2;
    }

    previous.addEventListener("click", () => step(-1));
    next.addEventListener("click", () => step(1));

    window.addEventListener("keydown", event => {
        if (["ArrowDown", "ArrowRight", "PageDown", " "].includes(event.key)) {
            event.preventDefault();
            step(1);
        } else if (["ArrowUp", "ArrowLeft", "PageUp"].includes(event.key)) {
            event.preventDefault();
            step(-1);
        } else if (event.key === "Home") {
            event.preventDefault();
            show(0);
        } else if (event.key === "End") {
            event.preventDefault();
            show(slides.length - 1);
        }
    });

    window.addEventListener("wheel", event => {
        const direction = Math.sign(event.deltaY);
        if (!direction || activeContentCanScroll(direction)) return;
        event.preventDefault();
        if (wheelLocked) return;
        wheelLocked = true;
        step(direction);
        window.setTimeout(() => {
            wheelLocked = false;
        }, reducedMotion.matches ? 80 : 650);
    }, { passive: false });

    window.addEventListener("touchstart", event => {
        touchStartY = event.changedTouches[0]?.clientY ?? null;
    }, { passive: true });

    window.addEventListener("touchend", event => {
        if (touchStartY === null) return;
        const endY = event.changedTouches[0]?.clientY ?? touchStartY;
        const delta = touchStartY - endY;
        touchStartY = null;
        if (Math.abs(delta) > 54 && !activeContentCanScroll(Math.sign(delta))) {
            step(Math.sign(delta));
        }
    }, { passive: true });

    const match = window.location.hash.match(/chapter-(\d+)/);
    show(match ? Number(match[1]) - 1 : 0, false);
})();
