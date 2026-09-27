-- Plot count and ids
local PlotConfig = {}

PlotConfig.PLOT_COUNT = 4

function PlotConfig.GetPlotIds()
	local ids = {}
	for i = 1, PlotConfig.PLOT_COUNT do
		ids[i] = i
	end
	return ids
end

return PlotConfig
