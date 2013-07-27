//http://jquery.bassistance.de/validate/demo/   
//
// VALIDATE TRAVEL TIME QUICK FORM
//

//     Form Validate
$(document).ready(function() {
// validate :form on keyup and submit

$("#quick_form").validate({
//    debug: true,  //form wont submit
    rules: {
          "address-1" : {
          required: true,
          rangelength: [3,80],
        },
          "address-2" : {
          required: true,
          rangelength: [3,80],
        },
    },
        messages: {
          "address-1" : {
                required : "Please enter a City/Town,State,and County using the selector",
                rangelength : "You must enter City/Town,State,County using the selector.",
            }, 
          "address-2" : {
                required : "Please enter a City/Town,State,and County using the selector",
                rangelength : "You must enter City/Town,State,County using the selector.",
            }
     }, 
     highlight: function(element) {
            $(element).closest('.control-group').removeClass('success').addClass('error');
      },
     success: function(element) {
          element
  //        .text('OK!').addClass('valid')
          .addClass('valid')
              .closest('.control-group').removeClass('error').addClass('success');
      }
});


});//End of document ready function





///Generic class rules
/*
jQuery.validator.addClassRules({
 //Covers all Quick Address fields
 cityStatesTypeahead: {
      required: true,
      rangelength: [3,80],
    }, 
  zip: {
      required: true, 
      digits: true, 
      minlength: 5, 
    }, 
});
*/
