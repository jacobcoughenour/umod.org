$(document).ready(function() {
    // Write any custom functions here. All the necessary plugins are already loaded.

    $('h2,h3,h4,h5,h6').filter('[id]').each(function () {
        $(this).html('<a href="#' + $(this).attr('id') + '" class="fragment-identifier js-fragment-identifier fragment-identifier-scroll"><i class="fa fa-link"></i></a>'+ $(this).text());
    });
});
