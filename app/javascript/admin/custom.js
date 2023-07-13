// This overrides the default clear filters button of AA to use the parameter 'commit=clear_filters'. This is
// necessary because we are persisting the filters in the session store, and need to pass this parameter for
// the AA controller's :before_filter to clear the session filters.
// The way we are clearing the events for the clear filters button is be a bit hacky, but it works.
//
// See aa_filters_persistence.rb for more details.

$(function() {
    $(document).off('click', '.clear_filters_btn');
    $('.clear_filters_btn').attr('href', '?commit=clear_filters');
})

