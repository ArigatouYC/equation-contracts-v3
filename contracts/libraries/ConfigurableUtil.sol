// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "../core/interfaces/IConfigurable.sol";

library ConfigurableUtil {
    function enableMarket(
        mapping(IMarketDescriptor => IConfigurable.MarketConfig) storage _self,
        IMarketDescriptor _market,
        IConfigurable.MarketConfig calldata _cfg
    ) public {
        if (_self[_market].baseConfig.maxLeveragePerLiquidityPosition > 0)
            revert IConfigurable.MarketAlreadyEnabled(_market);

        _validateBaseConfig(_cfg.baseConfig);
        _validateFeeRateConfig(_cfg.feeRateConfig);
        _validatePriceConfig(_cfg.priceConfig);

        _self[_market] = _cfg;

        emit IConfigurable.MarketConfigEnabled(_market, _cfg.baseConfig, _cfg.feeRateConfig, _cfg.priceConfig);
    }

    function updateMarketBaseConfig(
        mapping(IMarketDescriptor => IConfigurable.MarketConfig) storage _self,
        IMarketDescriptor _market,
        IConfigurable.MarketBaseConfig calldata _newCfg
    ) public {
        IConfigurable.MarketConfig storage marketCfg = _self[_market];
        if (marketCfg.baseConfig.maxLeveragePerLiquidityPosition == 0) revert IConfigurable.MarketNotEnabled(_market);

        _validateBaseConfig(_newCfg);

        marketCfg.baseConfig = _newCfg;

        emit IConfigurable.MarketBaseConfigChanged(_market, _newCfg);
    }

    function updateMarketFeeRateConfig(
        mapping(IMarketDescriptor => IConfigurable.MarketConfig) storage _self,
        IMarketDescriptor _market,
        IConfigurable.MarketFeeRateConfig calldata _newCfg
    ) public {
        IConfigurable.MarketConfig storage marketCfg = _self[_market];
        if (marketCfg.baseConfig.maxLeveragePerLiquidityPosition == 0) revert IConfigurable.MarketNotEnabled(_market);

        _validateFeeRateConfig(_newCfg);

        marketCfg.feeRateConfig = _newCfg;

        emit IConfigurable.MarketFeeRateConfigChanged(_market, _newCfg);
    }

    function updateMarketPriceConfig(
        mapping(IMarketDescriptor => IConfigurable.MarketConfig) storage _self,
        IMarketDescriptor _market,
        IConfigurable.MarketPriceConfig calldata _newCfg
    ) public {
        IConfigurable.MarketConfig storage marketCfg = _self[_market];
        if (marketCfg.baseConfig.maxLeveragePerLiquidityPosition == 0) revert IConfigurable.MarketNotEnabled(_market);

        _validatePriceConfig(_newCfg);

        marketCfg.priceConfig = _newCfg;

        emit IConfigurable.MarketPriceConfigChanged(_market, _newCfg);
    }

    function updateMarketMinProfitDuration(
        mapping(IMarketDescriptor => IConfigurable.MarketConfig) storage _self,
        mapping(IMarketDescriptor => uint16) storage _marketMinProfitDurations,
        IMarketDescriptor _market,
        uint16 _minProfitDuration
    ) public {
        IConfigurable.MarketConfig storage marketCfg = _self[_market];
        if (marketCfg.baseConfig.maxLeveragePerLiquidityPosition == 0) revert IConfigurable.MarketNotEnabled(_market);

        _marketMinProfitDurations[_market] = _minProfitDuration;

        emit IConfigurable.MarketMinProfitDurationChanged(_market, _minProfitDuration);
    }

    function _validateBaseConfig(IConfigurable.MarketBaseConfig calldata _newCfg) private pure {
        if (_newCfg.maxLeveragePerLiquidityPosition == 0)
            revert IConfigurable.InvalidMaxLeveragePerLiquidityPosition(_newCfg.maxLeveragePerLiquidityPosition);

        if (_newCfg.liquidationFeeRatePerLiquidityPosition > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidLiquidationFeeRatePerLiquidityPosition(
                _newCfg.liquidationFeeRatePerLiquidityPosition
            );

        if (_newCfg.maxLeveragePerPosition == 0)
            revert IConfigurable.InvalidMaxLeveragePerPosition(_newCfg.maxLeveragePerPosition);

        if (_newCfg.liquidationFeeRatePerPosition > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidLiquidationFeeRatePerPosition(_newCfg.liquidationFeeRatePerPosition);

        if (_newCfg.maxPositionLiquidity == 0)
            revert IConfigurable.InvalidMaxPositionLiquidity(_newCfg.maxPositionLiquidity);

        if (_newCfg.maxPositionValueRate == 0)
            revert IConfigurable.InvalidMaxPositionValueRate(_newCfg.maxPositionValueRate);

        if (_newCfg.maxSizeRatePerPosition > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMaxSizeRatePerPosition(_newCfg.maxSizeRatePerPosition);
    }

    function _validateFeeRateConfig(IConfigurable.MarketFeeRateConfig calldata _newCfg) private pure {
        if (_newCfg.protocolFundingFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidProtocolFundingFeeRate(_newCfg.protocolFundingFeeRate);

        if (_newCfg.fundingCoeff > Constants.BASIS_POINTS_DIVISOR * 10)
            revert IConfigurable.InvalidFundingCoeff(_newCfg.fundingCoeff);

        if (_newCfg.protocolFundingCoeff > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidProtocolFundingCoeff(_newCfg.protocolFundingCoeff);

        if (_newCfg.interestRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidInterestRate(_newCfg.interestRate);

        if (_newCfg.fundingBuffer > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidFundingBuffer(_newCfg.fundingBuffer);

        if (_newCfg.liquidityFundingFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidLiquidityFundingFeeRate(_newCfg.liquidityFundingFeeRate);

        if (_newCfg.maxFundingRate > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidMaxFundingRate(_newCfg.maxFundingRate);
    }

    function _validatePriceConfig(IConfigurable.MarketPriceConfig calldata _newCfg) private pure {
        if (_newCfg.maxPriceImpactLiquidity == 0)
            revert IConfigurable.InvalidMaxPriceImpactLiquidity(_newCfg.maxPriceImpactLiquidity);

        if (_newCfg.vertices.length != Constants.VERTEX_NUM)
            revert IConfigurable.InvalidVerticesLength(_newCfg.vertices.length, Constants.VERTEX_NUM);

        if (_newCfg.liquidationVertexIndex >= Constants.LATEST_VERTEX)
            revert IConfigurable.InvalidLiquidationVertexIndex(_newCfg.liquidationVertexIndex);

        if (_newCfg.dynamicDepthLevel > Constants.BASIS_POINTS_DIVISOR)
            revert IConfigurable.InvalidDynamicDepthLevel(_newCfg.dynamicDepthLevel);

        unchecked {
            // first vertex must be (0, 0)
            if (_newCfg.vertices[0].balanceRate != 0 || _newCfg.vertices[0].premiumRate != 0)
                revert IConfigurable.InvalidVertex(0);

            for (uint8 i = 2; i < Constants.VERTEX_NUM; ++i) {
                if (
                    _newCfg.vertices[i - 1].balanceRate > _newCfg.vertices[i].balanceRate ||
                    _newCfg.vertices[i - 1].premiumRate > _newCfg.vertices[i].premiumRate
                ) revert IConfigurable.InvalidVertex(i);
            }
            if (
                _newCfg.vertices[Constants.LATEST_VERTEX].balanceRate > Constants.BASIS_POINTS_DIVISOR ||
                _newCfg.vertices[Constants.LATEST_VERTEX].premiumRate > Constants.BASIS_POINTS_DIVISOR
            ) revert IConfigurable.InvalidVertex(Constants.LATEST_VERTEX);
        }
    }
}
