// jQuery Functions
$(document).ready(function(){


//        BOOTSTRAP TYPEAHEAD
// Use the key word "typeahead" instead of "autocomplete" to access the
// Bootstrap typeahead/autocomplete component.

var hiddenId;
// Get the hidden address field associated with the current
// address field
$('.cityStatesTypeahead').bind('focus',  function(){
   hiddenId =  $(this).attr('id'); 
});

$(".cityStatesTypeahead").typeahead({
  items: 10, 
  minLength : 3, 
  source:  function(query, process) {
      //Call Perl App to find the sorted list of City, States and Counties
      return searchForPlaces(query, process);
 },  
  highlighter: function(item){
    return highLightSelect(item);
},  

matcher: function () { return true; }, 
 
updater: function (item) {
    return updateField(item);
}, 

});
// Ajax call to Perl Dancer Script, which returns an Array Ref
// of sorted City, State and County data.
var debounceWait = 100;
// Use Underscore JS function '_debounce' to ensure that the
// search waits for specific number of miliseconds before running again.
var cityStates = {};
var cityNames = [];
var searchForPlaces = _.debounce(function( query,  process ){
    $.post("/city_states",{ find : query}, function(data){
    cityStates = {};
    cityNames = [];
        var counter = 0;
        console.log('Got this City State Data: ' + data.city_states);
    _.each( data.city_states,  function( item,  ix,  list ){
        item.label = item + '-' + (counter++);
         console.log('Got this item from AJAX : ' + item);
        cityStates[item.label] = {
                city : item[0],   
                state : item[1],  
                county : item[2]
        };
        //add selected items to diaplay array
        console.log('Add this to the array ' + item.label);
        cityNames.push(item.label);

    });
    // Let Bootstrap and jQuery process the list
    // for display in the input box
    process( cityNames );
});
},  debounceWait);

//Highlighter Function
var highLightSelect = function(item){
    console.log("      Item inside hilighter " + item);
   var c = cityStates[item];
   return ''
       + "<div class='typeahead_wrapper'>"
       + "<div class='typeahead_labels'>"
       + "<div class='typeahead_primary'>" + c.city + ', ' + c.state + "</div>"
       + "<div class='typeahead_secondary'><strong>County: </strong>"  + c.county + "</div>"
       + "</div>"
       + "</div>";
};

// Updater Function
// Add the required data into the input field
var updateField = function(item){
   var c = cityStates[item];
   console.log("      Item inside Updater " + c);
   //Hidden field will contain all the valuable data
    $( "#h-" + hiddenId ).val( c.city + ',' + c.state + ',' + c.county );
   //This is the data for diaplay on input box
   return c.city + ', ' + c.state + "  County: " + c.county ;
};

//      END BOOTSTRAP TYPEAHEAD

// Focus on first address field
// Note: Do not put this before the typeahead as it will
//       disable it.
$("#address-1").focus();
$('.addQmark').popover({
     trigger: "hover click", 
     title : "Location Selector", 
     html  : true, 
     animation: true, 
     placement : "right", 
     delay    : 100, 
     content : "<p>Start typing the name of the City or Town until the town you are looking for appears highlighted in the list. Select this by hitting the Enter button or clicking on it with the mouse.  If the City/Town dosent appear on the list, continue to type the full state name after a comma.<br />  As In: Greenwich,Connecticut </p>"
});




});
