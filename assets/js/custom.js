$(document).ready(function() {
    // Write any custom functions here. All the necessary plugins are already loaded.

    $('h2,h3,h4,h5,h6').filter('[id]').each(function () {
        $(this).html('<a href="#' + $(this).attr('id') + '" class="fragment-identifier js-fragment-identifier fragment-identifier-scroll"><i class="fa fa-link"></i></a>'+ $(this).text());
    });

    $('.topics.scroll').each(function () {AttachHorizontalScroll(this);});
});

function AttachHorizontalScroll(element) {
    let shadowLeft = $("<div>").addClass("scroll-shadow-left").insertBefore($("ul", element));
    let shadowRight = $("<div>").addClass("scroll-shadow-right").insertAfter($("ul", element));

    $("ul", element)
        .data('shadowLeft', shadowLeft)
        .data('shadowRight', shadowRight)
    .mousedown(function (e) {
        $(this).data('down', true).data('x', e.clientX).data('scrollLeft', this.scrollLeft);
        return false;
    }).mouseup(function (e) {
        $(this).data('down', false).removeClass("dragging");
    }).mouseleave(function (e) {
        $(this).data('down', false).removeClass("dragging");
    }).mousemove(function (e) {
        if ($(this).data('down') == true) {
            $(this).toggleClass("dragging", true);
            this.scrollLeft = $(this).data('scrollLeft') + $(this).data('x') - e.clientX;
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
        if (e.target.offsetWidth === 0) {
            $(e.target).data('shadowRight').css("width", '50px');
        } else if (e.target.scrollWidth > e.target.offsetWidth) {
            $(e.target).data('shadowLeft').css("width", Math.min(e.target.scrollLeft, 50) + 'px');
            $(e.target).data('shadowRight').css("width", Math.min(e.target.scrollWidth - e.target.scrollLeft - e.target.offsetWidth, 50) + 'px');
        } else {
            $(e.target).data('shadowLeft').css("width", '0px');
            $(e.target).data('shadowRight').css("width", '0px');
        }
    }).css({ "overflow": "hidden" }).trigger("UpdateShadows");

}