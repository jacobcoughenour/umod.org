$(document).ready(function() {
    // Write any custom functions here. All the necessary plugins are already loaded.

    $('h2,h3,h4,h5,h6').filter('[id]').each(function () {
        $(this).html('<a href="#' + $(this).attr('id') + '" class="fragment-identifier js-fragment-identifier fragment-identifier-scroll"><i class="fa fa-link"></i></a>'+ $(this).text());
    });

    $('.topics.scroll').each(function () {AttachHorizontalScroll(this);});
});

function AttachHorizontalScroll(element) {
    $("ul", element)
        .data('shadowLeft', $("<a>").addClass("scroll-shadow-left").insertBefore($("ul", element)).html('<i class="fa fa-chevron-left" aria-hidden="true"></i>').mousedown(function (e) {
            let ul = $("ul", this.parentNode);
            ul.animate({ scrollLeft: "-=" + (ul.width() * 0.5) }, { step: (n, fx) => { $(fx.elem).trigger("UpdateShadows"); } });
        }))
        .data('shadowRight', $("<a>").addClass("scroll-shadow-right").insertAfter($("ul", element)).html('<i class="fa fa-chevron-right" aria-hidden="true"></i>').mousedown(function (e) {
            let ul = $("ul", this.parentNode);
            ul.animate({ scrollLeft: "+=" + (ul.width() * 0.5) }, { step: (n, fx) => { $(fx.elem).trigger("UpdateShadows"); } });
        }))
        .mousedown(function (e) {
            if (this.scrollWidth > this.offsetWidth)
                $(this).data('down', true).data('x', e.clientX).data('scrollLeft', this.scrollLeft);
            return false;
        }).mouseup(function (e) {
            $(this).data('down', false).removeClass("dragging");
        }).mouseleave(function (e) {
            $(this).data('down', false).removeClass("dragging");
        }).mousemove(function (e) {
            let dist = $(this).data('x') - e.clientX;
            if ($(this).data('down') == true && (Math.abs(dist) > 16 || $(this).hasClass("dragging"))) {
                $(this).toggleClass("dragging", true);
                this.scrollLeft = $(this).data('scrollLeft') + dist;
                $(this).trigger("UpdateShadows");
            }
        }).mousewheel(function (e, delta) {
            if (this.scrollWidth > this.offsetWidth) {
                this.scrollLeft -= (delta * 32);
                e.preventDefault();
                $(this).trigger("UpdateShadows");
                return false;
            }
        }).on("UpdateShadows", e => {
            if (e.target.scrollWidth > e.target.offsetWidth) {
                $(e.target).data('shadowLeft').css("width", Math.min(e.target.scrollLeft, 50) + 'px');
                $(e.target).data('shadowRight').css("width", Math.min(e.target.scrollWidth - e.target.scrollLeft - e.target.offsetWidth, 50) + 'px');
            } else {
                $(e.target).data('shadowLeft').css("width", '0px');
                $(e.target).data('shadowRight').css("width", '0px');
            }
        }).css({ "overflow": "hidden" }).trigger("UpdateShadows");
}