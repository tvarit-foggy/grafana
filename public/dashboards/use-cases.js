/* global _ */

'use strict';

return function (callback) {
  $.getJSON('/public/dashboards/use-cases.json', function(data) {
    callback(data);
  });
};
